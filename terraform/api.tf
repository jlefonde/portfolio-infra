locals {
  api_lambdas = {
    visitor-count = {
      handler       = "bootstrap"
      runtime       = "provided.al2"
      source_file   = "${var.lambda_build_dir}/bootstrap.zip"
      use_s3        = true
      s3_bucket     = aws_s3_bucket.backend.bucket
      s3_key        = "lambdas/visitor_count.zip"
      enable_log    = true
      log_retention = var.lambda_log_retention
      policy_statements = [
        {
          sid = "AllowLambdaServiceAccessDynamoDb"
          actions = [
            "dynamodb:GetItem",
            "dynamodb:UpdateItem"
          ]
          resources = [module.dynamodb["visitor-count"].table_arn]
        }
      ]
    },
    origin-verify-authorizer = {
      handler       = "bootstrap"
      runtime       = "provided.al2"
      source_file   = "${var.lambda_build_dir}/api_authorizer.zip"
      publish       = true
      enable_log    = true
      log_retention = var.lambda_log_retention
      environment = {
        CLOUDFRONT_ORIGIN_VERIFY_HEADER = module.cdn.origin_verify_header
        SECRET_NAME                     = local.origin_verify_secret_name
      }
      policy_statements = [
        {
          sid       = "AllowLamdaAccessOriginVerifySecret"
          actions   = ["secretsmanager:GetSecretValue"]
          resources = [module.secrets[local.origin_verify_secret_name].secret_arn]
        }
      ]
    }
  }

  api_config = {
    name          = "${var.domain_name}-api"
    description   = "HTTP API with Lambda integrations"
    protocol_type = "HTTP"

    authorizers = {
      origin-verify = {
        identity_sources                  = ["$request.header.${module.cdn.origin_verify_header}"]
        name                              = "origin-verify-authorizer"
        authorizer_payload_format_version = "2.0"
        enable_simple_responses           = true
      }
    }

    routes = {
      "GET /api/visitors/{id}" = {
        authorizer_key     = "origin-verify"
        authorization_type = "CUSTOM"
        integration = {
          lambda_key             = "visitor-count"
          method                 = "POST"
          payload_format_version = "2.0"
        }
      },
      "POST /api/visitors/{id}" = {
        authorizer_key     = "origin-verify"
        authorization_type = "CUSTOM"
        integration = {
          lambda_key             = "visitor-count"
          method                 = "POST"
          payload_format_version = "2.0"
        }
      }
    }
  }
}

module "api_lambdas" {
  source   = "./modules/lambda"
  for_each = local.api_lambdas

  lambda_name   = each.key
  lambda_config = each.value
}

locals {
  api_authorizers = {
    for auth_key, auth_config in local.api_config.authorizers : auth_key => merge(
      auth_config,
      {
        authorizer_uri = module.api_lambdas[auth_config.name].lambda_function_invoke_arn
      }
    )
  }

  api_routes = {
    for route_key, route_config in local.api_config.routes : route_key => merge(
      route_config,
      {
        integration = merge(
          route_config.integration,
          {
            uri = module.api_lambdas[route_config.integration.lambda_key].lambda_function_invoke_arn
          }
        )
      }
    )
  }
}

module "api_gateway" {
  source = "./modules/api_gateway"

  api_name            = local.api_config.name
  api_description     = local.api_config.description
  api_protocol_type   = "HTTP"
  api_ip_address_type = "dualstack"

  authorizers = local.api_authorizers
  routes      = local.api_routes
}

resource "aws_lambda_permission" "api_gateway_invoke" {
  for_each = {
    for route_key, route_config in local.api_config.routes :
    route_config.integration.lambda_key => route_key...
  }

  statement_id  = "AllowAPIGatewayInvoke-${each.key}"
  function_name = module.api_lambdas[each.key].lambda_function_name
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${module.api_gateway.api_execution_arn}/*/*"
}

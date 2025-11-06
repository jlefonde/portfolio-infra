locals {
  origin_verify_secret_name = "${var.project_name}/cloudfront/origin-verify-2"

  secrets = {
    (local.origin_verify_secret_name) = {
      description = "Verify the origin of API requests"
      secret_config = {
        password_length     = 32
        exclude_punctuation = true
      }
    }
  }
}

module "secrets" {
  source   = "./modules/secret"
  for_each = local.secrets

  secret_name        = each.key
  secret_description = each.value.description
  secret_config      = each.value.secret_config
}

locals {
  rotation_lambdas = {
    rotate-origin-verify = {
      handler       = "bootstrap"
      runtime       = "provided.al2"
      source_dir    = "${path.root}/../lambda/rotate_secret/bin/rotate_origin_verify"
      publish       = true
      enable_log    = true
      log_retention = var.lambda_log_retention
      environment = {
        CLOUDFRONT_DISTRIBUTION_ID      = module.cdn.distribution_id
        CLOUDFRONT_ORIGIN_ID            = module.cdn.backend_origin_id
        CLOUDFRONT_ORIGIN_VERIFY_HEADER = module.cdn.origin_verify_header
        SECRET_PASSWORD_LENGTH          = 32
        SECRET_EXCLUDE_PUNCTUATION      = true
      }
      policy_statements = [
        {
          sid       = "AllowGetRandomPassword"
          actions   = ["secretsmanager:GetRandomPassword"]
          resources = ["*"]
        },
        {
          sid = "AllowLambdaServiceUpdateSecretsManager"
          actions = [
            "secretsmanager:DescribeSecret",
            "secretsmanager:UpdateSecret",
            "secretsmanager:UpdateSecretVersionStage",
            "secretsmanager:GetSecretValue",
            "secretsmanager:PutSecretValue"
          ]
          resources = [module.secrets[local.origin_verify_secret_name].secret_arn]
        },
        {
          sid = "AllowLambdaServiceUpdateCloudFront"
          actions = [
            "cloudfront:GetDistributionConfig",
            "cloudfront:UpdateDistribution"
          ]
          resources = [module.cdn.distribution_arn]
        }
      ]
    }
  }
}

module "rotation_lambdas" {
  source   = "./modules/lambda"
  for_each = local.rotation_lambdas

  lambda_name   = each.key
  lambda_config = each.value
}

locals {
  secret_rotations = {
    (local.origin_verify_secret_name) = {
      lambda_key               = "rotate-origin-verify"
      automatically_after_days = var.origin_verify_rotation
    }
  }
}

resource "aws_lambda_permission" "secretsmanager_invoke" {
  for_each = local.secret_rotations

  statement_id  = "AllowSecretsManagerInvoke-${each.value.lambda_key}"
  function_name = module.rotation_lambdas[each.value.lambda_key].lambda_function_name
  action        = "lambda:InvokeFunction"
  principal     = "secretsmanager.amazonaws.com"
}

resource "aws_secretsmanager_secret_rotation" "this" {
  for_each = local.secret_rotations

  secret_id           = module.secrets[each.key].secret_id
  rotation_lambda_arn = module.rotation_lambdas[each.value.lambda_key].lambda_function_arn

  rotation_rules {
    automatically_after_days = each.value.automatically_after_days
  }
}

locals {
  lambda_functions = {
    rotate-origin-verify = {
      handler       = "bootstrap"
      runtime       = "provided.al2"
      source_dir    = "${path.module}/../../lambda/rotate_secret/bin/rotate_origin_verify"
      publish       = true
      enable_log    = true
      log_retention = var.lambda_log_retention
      environment = {
        CLOUDFRONT_DISTRIBUTION_ID      = module.cdn.distribution_arn
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
          resources = [aws_secretsmanager_secret.origin_verify.arn]
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

module "cdn" {
  source = "../../modules/cdn"

  zone_name = var.zone_name
  domain_name = var.domain_name
  acm_wildcard = var.acm_wildcard
  frontend_origin_cache_policy = var.cloudfront_frontend_origin_cache_policy
  backend_origin_cache_policy = var.cloudfront_backend_origin_cache_policy
  origin_verify_header_value = aws_secretsmanager_secret_version.origin_verify.secret_string
  api_gateway_endpoint = module.api_gateway.api_endpoint
}

data "aws_secretsmanager_random_password" "origin_verify" {
  password_length     = 32
  exclude_punctuation = true
}

resource "aws_lambda_permission" "secretsmanager_invoke" {
  statement_id  = "AllowSecretsManagerInvoke"
  function_name = module.lambda["rotate-origin-verify"].lambda_function_name
  action        = "lambda:InvokeFunction"
  principal     = "secretsmanager.amazonaws.com"
}

resource "aws_secretsmanager_secret" "origin_verify" {
  name        = "${var.project_name}/cloudfront/origin-verify"
  description = "Verify the origin of API requests"
}

resource "aws_secretsmanager_secret_version" "origin_verify" {
  secret_id     = aws_secretsmanager_secret.origin_verify.id
  secret_string = data.aws_secretsmanager_random_password.origin_verify.random_password

  lifecycle {
    ignore_changes = [secret_string]
  }
}

resource "aws_secretsmanager_secret_rotation" "origin_verify" {
  secret_id           = aws_secretsmanager_secret.origin_verify.id
  rotation_lambda_arn = module.lambda["rotate-origin-verify"].lambda_function_arn

  rotation_rules {
    automatically_after_days = var.origin_verify_rotation
  }
}

module "dynamodb" {
  source = "../../modules/dynamodb"

  for_each = {
    visitor-count = {
      hash_key     = "id"
      billing_mode = "PAY_PER_REQUEST"

      attributes = [
        {
          name = "id"
          type = "S"
        }
      ]
    }
  }

  table_name   = "${var.project_name}-${each.key}"
  table_config = each.value
}

resource "aws_s3_bucket" "backend" {
  bucket        = "${var.domain_name}-backend"
  force_destroy = true
}

module "lambda" {
  source   = "../../modules/lambda"
  for_each = local.lambda_functions

  lambda_name   = each.key
  lambda_config = each.value
}

module "cdn" {
  source = "../../modules/cdn"

  zone_name                    = var.zone_name
  domain_name                  = var.domain_name
  acm_wildcard                 = var.acm_wildcard
  frontend_origin_cache_policy = var.cloudfront_frontend_origin_cache_policy
  backend_origin_cache_policy  = var.cloudfront_backend_origin_cache_policy
  origin_verify_header_value   = module.secrets[local.origin_verify_secret_name].secret_string
  api_gateway_endpoint         = module.api_gateway.api_endpoint
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

resource "aws_ssm_parameter" "frontend_bucket_arn" {
  name  = "/${var.project_name}/s3/frontend-bucket-arn"
  type  = "String"
  value = module.cdn.frontend_bucket_arn
}

resource "aws_ssm_parameter" "backend_bucket_arn" {
  name  = "/${var.project_name}/s3/backend-bucket-arn"
  type  = "String"
  value = aws_s3_bucket.backend.arn
}

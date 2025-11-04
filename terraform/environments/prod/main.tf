resource "aws_route53_zone" "this" {
  name = var.zone_name
}

module "cdn" {
  source = "../../modules/cdn"

  zone_id                      = aws_route53_zone.this.zone_id
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

resource "aws_ssm_parameter" "frontend_bucket_name" {
  name  = "/${var.project_name}/s3/frontend-bucket-name"
  type  = "String"
  value = module.cdn.frontend_bucket_name
}

resource "aws_ssm_parameter" "backend_bucket_name" {
  name  = "/${var.project_name}/s3/backend-bucket-name"
  type  = "String"
  value = aws_s3_bucket.backend.bucket
}

resource "aws_ssm_parameter" "distribution_id" {
  name  = "/${var.project_name}/cloudfront/distribution-id"
  type  = "String"
  value = module.cdn.distribution_id
}

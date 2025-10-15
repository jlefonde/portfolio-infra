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
        CLOUDFRONT_DISTRIBUTION_ID      = aws_cloudfront_distribution.main.id
        CLOUDFRONT_ORIGIN_ID            = var.backend_origin_id
        CLOUDFRONT_ORIGIN_VERIFY_HEADER = var.cloudfront_origin_verify_header
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
          resources = [aws_cloudfront_distribution.main.arn]
        }
      ]
    }
  }
}

resource "aws_s3_bucket" "frontend" {
  bucket        = "${var.domain_name}-frontend"
  force_destroy = true
}

data "aws_iam_policy_document" "cloudfront_s3_access" {
  statement {
    sid    = "AllowCloudFrontServicePrincipal"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.frontend.arn}/*"]

    condition {
      test     = "ArnLike"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.main.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "frontend_bucket_access" {
  bucket = aws_s3_bucket.frontend.bucket
  policy = data.aws_iam_policy_document.cloudfront_s3_access.json
}

data "aws_acm_certificate" "frontend" {
  region   = "us-east-1"
  domain   = var.acm_wildcard
  statuses = ["ISSUED"]
}

data "aws_acm_certificate" "backend" {
  domain   = var.acm_wildcard
  statuses = ["ISSUED"]
}

resource "aws_cloudfront_origin_access_control" "default" {
  name                              = "default-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_secretsmanager_random_password" "origin_verify" {
  password_length     = 32
  exclude_punctuation = true
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_distribution" "main" {
  origin {
    origin_id                = var.frontend_origin_id
    domain_name              = aws_s3_bucket.frontend.bucket_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.default.id
  }

  origin {
    origin_id   = var.backend_origin_id
    domain_name = replace(module.api_gateway.api_endpoint, "https://", "")

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = var.cloudfront_origin_verify_header
      value = aws_secretsmanager_secret_version.origin_verify.secret_string
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  default_cache_behavior {
    allowed_methods  = ["HEAD", "GET"]
    cached_methods   = ["HEAD", "GET"]
    target_origin_id = var.frontend_origin_id

    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = var.cloudfront_cache_policy_ids.caching_optimized
  }

  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["HEAD", "GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    cached_methods   = ["HEAD", "GET"]
    target_origin_id = var.backend_origin_id

    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = var.cloudfront_cache_policy_ids.caching_disabled
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.frontend.arn
    ssl_support_method  = "sni-only"
  }

  enabled             = true
  is_ipv6_enabled     = true
  aliases             = [var.domain_name]
  comment             = "CloudFront distribution to distribute frontend"
  default_root_object = "index.html"

  lifecycle {
    ignore_changes = [origin]
  }
}

data "aws_route53_zone" "primary" {
  name = var.zone_name
}

resource "aws_route53_record" "cloudfront_ipv4" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    name                   = aws_cloudfront_distribution.main.domain_name
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cloudfront_ipv6" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = var.domain_name
  type    = "AAAA"
  alias {
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    name                   = aws_cloudfront_distribution.main.domain_name
    evaluate_target_health = false
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

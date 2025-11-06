locals {
  # See: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-cache-policies.html
  cloudfront_cache_policy_ids = {
    CachingDisabled  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    CachingOptimized = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }
  cloudfront_origin_verify_header = "x-origin-verify"
  frontend_origin_id              = "frontend-origin"
  backend_origin_id               = "backend-origin"
}

data "aws_acm_certificate" "frontend" {
  region   = "us-east-1"
  domain   = var.acm_wildcard
  statuses = ["ISSUED"]
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

resource "aws_cloudfront_origin_access_control" "default" {
  name                              = "default-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_distribution" "main" {
  origin {
    origin_id                = local.frontend_origin_id
    domain_name              = aws_s3_bucket.frontend.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.default.id
  }

  origin {
    origin_id   = local.backend_origin_id
    domain_name = replace(var.api_gateway_endpoint, "https://", "")

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = local.cloudfront_origin_verify_header
      value = var.origin_verify_header_value
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
    target_origin_id = local.frontend_origin_id

    viewer_protocol_policy = "redirect-to-https"
    cache_policy_id        = lookup(local.cloudfront_cache_policy_ids, var.frontend_origin_cache_policy)
  }

  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["HEAD", "GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    cached_methods   = ["HEAD", "GET"]
    target_origin_id = local.backend_origin_id

    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = lookup(local.cloudfront_cache_policy_ids, var.backend_origin_cache_policy)
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  viewer_certificate {
    acm_certificate_arn      = data.aws_acm_certificate.frontend.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
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

resource "aws_route53_record" "cloudfront_ipv4" {
  zone_id = var.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    name                   = aws_cloudfront_distribution.main.domain_name
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cloudfront_ipv6" {
  zone_id = var.zone_id
  name    = var.domain_name
  type    = "AAAA"
  alias {
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    name                   = aws_cloudfront_distribution.main.domain_name
    evaluate_target_health = false
  }
}

provider "aws" {
  region = "eu-central-1"
}

resource "aws_s3_bucket" "frontend" {
  bucket = "${var.domain_name}-frontend"

  tags = {
    Environment = var.environment
  }
}

data "aws_iam_policy_document" "cloudfront_s3_access" {
  policy_id = "PolicyForCloudFrontPrivateContent"

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
      values   = [aws_cloudfront_distribution.frontend.arn]
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

resource "aws_cloudfront_origin_access_control" "default" {
  name                              = "default-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_distribution" "frontend" {
  origin {
    origin_id                = var.frontend_origin_id
    domain_name              = aws_s3_bucket.frontend.bucket_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.default.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
      locations        = []
    }
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = var.frontend_origin_id

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = var.cloudfront_min_ttl
    default_ttl            = var.cloudfront_default_ttl
    max_ttl                = var.cloudfront_max_ttl

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.frontend.arn
    ssl_support_method = "sni-only"
  }

  enabled             = true
  is_ipv6_enabled     = true
  aliases             = [var.domain_name]
  comment             = "CloudFront distribution to distribute frontend"
  default_root_object = "index.html"

  tags = {
    Environment = var.environment
  }
}

data "aws_route53_zone" "primary" {
  name = var.domain_name
}

resource "aws_route53_record" "cloudfront_ipv4" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = var.domain_name
  type    = "A"
  alias {
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    name                   = aws_cloudfront_distribution.frontend.domain_name
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cloudfront_ipv6" {
  zone_id = data.aws_route53_zone.primary.zone_id
  name    = var.domain_name
  type    = "AAAA"
  alias {
    zone_id                = aws_cloudfront_distribution.frontend.hosted_zone_id
    name                   = aws_cloudfront_distribution.frontend.domain_name
    evaluate_target_health = false
  }
}

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
# {
#     "Version": "2012-10-17",
#     "Statement": [
#         {
#             "Effect": "Allow",
#             "Action": [
#                 "dynamodb:BatchGetItem",
#                 "dynamodb:GetItem",
#                 "dynamodb:Query",
#                 "dynamodb:Scan",
#                 "dynamodb:BatchWriteItem",
#                 "dynamodb:PutItem",
#                 "dynamodb:UpdateItem"
#             ],
#             "Resource": "arn:aws:dynamodb:us-east-1:640983357613:table/VisitorCount"
#         },
#         {
#             "Effect": "Allow",
#             "Action": [
#                 "logs:CreateLogStream",
#                 "logs:PutLogEvents"
#             ],
#             "Resource": "arn:aws:logs:us-east-1:640983357613:*"
#         },
#         {
#             "Effect": "Allow",
#             "Action": "logs:CreateLogGroup",
#             "Resource": "*"
#         }
#     ]
# }
data "aws_iam_policy_document" "" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:BatchGetItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:Scan",
      "dynamodb:BatchWriteItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem"
    ]
    
    resources = []
  }
}

# locals {
#   api_config = yamldecode(file("../../config/api_definition.yml"))
#   lamda_function = { 
#     for route in local.api_config.api.routes :
#       route.function => route.function
#   }
# }

# resource "aws_apigatewayv2_api" "primary" {
#   name = "${var.domain_name}-api"
#   protocol_type = "HTTP"
#   ip_address_type = "dualstack"
#   description = "HTTP API with Lambda integrations"

#   cors_configuration {
#     allow_origins = ["https://${var.domain_name}"]
#     allow_methods = ["GET", "POST", "OPTIONS"]
#   }

#   tags = {
#     Environment = var.environment
#   }
# }

# resource "aws_lambda_function" "api" {
#   for_each = local.lamda_function

#   function_name = each.key
#   role = 
# }

# resource "aws_apigatewayv2_integration" "primary" {
#   for_each = {
#     for route in local.api_config.api.routes :
#       "${route.method} ${route.path}" => route
#   }

#   api_id = aws_apigatewayv2_api.primary.id
#   integration_type = "HTTP_PROXY"
#   integration_method = each.value.method
# }

# resource "aws_apigatewayv2_route" "primary" {
#   for_each = {
#     for route in local.api_config.api.routes :
#       "${route.method} ${route.path}" => route
#   }

#   api_id = aws_apigatewayv2_api.primary.id
#   route_key = "${each.value.method} ${each.value.path}"

#   target = "integrations/${aws_apigatewayv2_integration.primary[each.key].id}"
# }

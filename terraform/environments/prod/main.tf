provider "aws" {
  region = "eu-central-1"
}

locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

resource "aws_s3_bucket" "frontend" {
  bucket = "${var.domain_name}-frontend"

  tags = local.common_tags
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
    ssl_support_method  = "sni-only"
  }

  enabled             = true
  is_ipv6_enabled     = true
  aliases             = [var.domain_name]
  comment             = "CloudFront distribution to distribute frontend"
  default_root_object = "index.html"

  tags = local.common_tags
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

resource "aws_dynamodb_table" "tables" {
  for_each = var.dynamodb_tables

  name      = "${var.project_name}-${var.environment}-${each.key}"
  hash_key  = each.value.hash_key
  range_key = each.value.range_key

  billing_mode   = each.value.billing_mode
  read_capacity  = each.value.read_capacity
  write_capacity = each.value.write_capacity

  dynamic "attribute" {
    for_each = each.value.attributes

    content {
      name = attribute.value.name
      type = attribute.value.type
    }
  }

  dynamic "global_secondary_index" {
    for_each = each.value.global_secondary_indexes != null ? each.value.global_secondary_indexes : []

    content {
      name            = global_secondary_index.value.name
      hash_key        = global_secondary_index.value.hash_key
      range_key       = global_secondary_index.value.range_key
      projection_type = global_secondary_index.value.projection_type
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-${var.environment}-${each.key}"
  })
}

resource "aws_s3_bucket" "backend" {
  bucket = "${var.domain_name}-backend"

  tags = local.common_tags
}

resource "aws_s3_object" "bootstrap_lambda" {
  bucket = aws_s3_bucket.backend.bucket
  key    = "bootstrap/bootstrap.zip"
  source = "../../lambda/bootstrap/bootstrap.zip"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    sid    = "AllowLambdaServiceAssumeRole"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

// TODO: add CreateLogStream/PutLogEvents, CreateLogGroup + combine with this one
data "aws_iam_policy_document" "lambda_dynamodb_access" {
  statement {
    sid    = "AllowLambdaServiceAccessDynamoDb"
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

    resources = [aws_dynamodb_table.tables["visitor_count"].arn]
  }
}

resource "aws_iam_policy" "lambda_api" {
  name   = "lambda-api-policy"
  policy = data.aws_iam_policy_document.lambda_dynamodb_access.json

  tags = local.common_tags
}

resource "aws_iam_role" "lambda_api" {
  name               = "lamdba-api-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "lambda_api_attach" {
  role       = aws_iam_role.lambda_api.name
  policy_arn = aws_iam_policy.lambda_api.arn
}

resource "aws_ssm_parameter" "lambda_s3_key" {
  name  = "/lambda/visitor-count/${var.environment}/s3-key"
  type  = "String"
  value = "bootstrap/bootstrap.zip"

  lifecycle {
    ignore_changes = [
      value,
    ]
  }
}

resource "aws_lambda_function" "api" {
  function_name = "visitor-count-${var.environment}"
  role          = aws_iam_role.lambda_api.arn
  publish       = true

  s3_bucket = aws_s3_bucket.backend.bucket
  s3_key    = aws_ssm_parameter.lambda_s3_key.value

  handler = "bootstrap"
  runtime = "provided.al2"

  tags = local.common_tags

  depends_on = [aws_s3_object.bootstrap_lambda]
  lifecycle {
    ignore_changes = [s3_key, source_code_hash]
  }
}

# locals {
#   api_config = yamldecode(file("../../config/api_definition.yml"))
#   lamda_function = { 
#     for route in local.api_config.api.routes :
#       route.function => route.function
#   }
# }

resource "aws_apigatewayv2_api" "primary" {
  name            = "${var.domain_name}-api"
  protocol_type   = "HTTP"
  ip_address_type = "dualstack"
  description     = "HTTP API with Lambda integrations"

  cors_configuration {
    allow_origins = ["https://${var.domain_name}"]
    allow_methods = ["GET", "POST", "OPTIONS"]
  }

  tags = local.common_tags
}

resource "aws_apigatewayv2_integration" "get_visitor_count" {
  api_id                 = aws_apigatewayv2_api.primary.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "post_visitor_count" {
  api_id                 = aws_apigatewayv2_api.primary.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_visitor_count" {
  api_id    = aws_apigatewayv2_api.primary.id
  route_key = "GET /visitor-count/{id}"

  target = "integrations/${aws_apigatewayv2_integration.get_visitor_count.id}"
}

resource "aws_apigatewayv2_route" "post_visitor_count" {
  api_id    = aws_apigatewayv2_api.primary.id
  route_key = "POST /visitor-count/{id}"

  target = "integrations/${aws_apigatewayv2_integration.post_visitor_count.id}"
}

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

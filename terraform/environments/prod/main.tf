locals {
  # See: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-cache-policies.html
  cloudfront_cache_policies = {
    caching_disabled  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    caching_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }

  lambda_functions = {
    rotate-origin-verify = {
      handler       = "bootstrap"
      runtime       = "provided.al2"
      bootstrap_dir = "${path.module}/../../lambda/rotate_secret/bin/rotate_origin_verify"
      log_retention = 14
      publish       = true
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
    domain_name = replace(aws_apigatewayv2_api.primary.api_endpoint, "https://", "")

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
    cache_policy_id        = local.cloudfront_cache_policies.caching_optimized
  }

  ordered_cache_behavior {
    path_pattern     = "/api/*"
    allowed_methods  = ["HEAD", "GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"]
    cached_methods   = ["HEAD", "GET"]
    target_origin_id = var.backend_origin_id

    viewer_protocol_policy   = "redirect-to-https"
    cache_policy_id          = local.cloudfront_cache_policies.caching_disabled
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

data "archive_file" "bootstrap_lambda" {
  type        = "zip"
  source_file = "${path.module}/../../lambda/bootstrap/bootstrap"
  output_path = "${path.module}/../../lambda/bootstrap/bootstrap.zip"
}

resource "aws_s3_object" "bootstrap_lambda" {
  bucket      = aws_s3_bucket.backend.bucket
  key         = "bootstrap/bootstrap.zip"
  source      = data.archive_file.bootstrap_lambda.output_path
  source_hash = data.archive_file.bootstrap_lambda.output_base64sha256
}

data "aws_iam_policy_document" "lambda_api" {
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

    resources = [module.dynamodb["visitor-count"].table_arn]
  }

  statement {
    sid    = "AllowLambdaServiceWriteLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "${aws_cloudwatch_log_group.lambda_visitor_count.arn}:*"
    ]
  }
}

resource "aws_cloudwatch_log_group" "lambda_visitor_count" {
  name              = "/aws/lambda/visitor-count"
  retention_in_days = var.lambda_log_retention
}

resource "aws_iam_policy" "lambda_api" {
  name   = "lambda-api-policy"
  policy = data.aws_iam_policy_document.lambda_api.json
}

resource "aws_iam_role" "lambda_api" {
  name               = "lamdba-api-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_api" {
  role       = aws_iam_role.lambda_api.name
  policy_arn = aws_iam_policy.lambda_api.arn
}

resource "aws_lambda_function" "api" {
  function_name = "visitor-count"
  role          = aws_iam_role.lambda_api.arn
  publish       = true

  s3_bucket = aws_s3_bucket.backend.bucket
  s3_key    = "bootstrap/bootstrap.zip"

  handler = "bootstrap"
  runtime = "provided.al2"

  depends_on = [aws_s3_object.bootstrap_lambda]
  lifecycle {
    ignore_changes = [s3_key, source_code_hash]
  }
}

resource "aws_apigatewayv2_api" "primary" {
  name            = "${var.domain_name}-api"
  protocol_type   = "HTTP"
  ip_address_type = "dualstack"
  description     = "HTTP API with Lambda integrations"

  cors_configuration {
    allow_origins = ["https://${var.domain_name}"]
    allow_methods = ["GET", "POST", "OPTIONS"]
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.primary.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigateway_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  function_name = aws_lambda_function.api.function_name
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.primary.execution_arn}/*/*/visitor-count/{id}"
}

resource "aws_apigatewayv2_integration" "visitor_count" {
  api_id                 = aws_apigatewayv2_api.primary.id
  integration_type       = "AWS_PROXY"
  integration_method     = "POST"
  integration_uri        = aws_lambda_function.api.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_visitor_count" {
  api_id    = aws_apigatewayv2_api.primary.id
  route_key = "GET /api/visitor-count/{id}"

  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.origin_verify.id

  target = "integrations/${aws_apigatewayv2_integration.visitor_count.id}"
}

resource "aws_apigatewayv2_route" "post_visitor_count" {
  api_id    = aws_apigatewayv2_api.primary.id
  route_key = "POST /api/visitor-count/{id}"

  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.origin_verify.id

  target = "integrations/${aws_apigatewayv2_integration.visitor_count.id}"
}

# TODO: remove
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

data "archive_file" "origin_verify_authorizer" {
  type        = "zip"
  source_file = "${path.module}/../../lambda/api_authorizer/bootstrap"
  output_path = "${path.module}/../../lambda/api_authorizer/origin_verify_authorizer.zip"
}

resource "aws_cloudwatch_log_group" "lambda_origin_verify_authorizer" {
  name              = "/aws/lambda/origin-verify-authorizer"
  retention_in_days = var.lambda_log_retention
}

data "aws_iam_policy_document" "lambda_origin_verify_secret_access" {
  statement {
    sid    = "AllowLamdaAccessOriginVerifySecret"
    effect = "Allow"

    actions = ["secretsmanager:GetSecretValue"]

    resources = [aws_secretsmanager_secret.origin_verify.arn]
  }

  statement {
    sid    = "AllowLambdaServiceWriteLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["${aws_cloudwatch_log_group.lambda_origin_verify_authorizer.arn}:*"]
  }
}

resource "aws_iam_policy" "lambda_origin_verify_authorizer" {
  name   = "lambda-origin-verify-authorizer"
  policy = data.aws_iam_policy_document.lambda_origin_verify_secret_access.json
}

resource "aws_iam_role" "lambda_origin_verify_authorizer" {
  name               = "lambda-origin-verify-authorizer-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "lambda_origin_verify_authorizer" {
  role       = aws_iam_role.lambda_origin_verify_authorizer.name
  policy_arn = aws_iam_policy.lambda_origin_verify_authorizer.arn
}

resource "aws_lambda_function" "origin_verify_authorizer" {
  function_name = "origin-verify-authorizer"
  role          = aws_iam_role.lambda_origin_verify_authorizer.arn
  publish       = true

  filename         = data.archive_file.origin_verify_authorizer.output_path
  source_code_hash = data.archive_file.origin_verify_authorizer.output_base64sha256
  handler          = "bootstrap"
  runtime          = "provided.al2"

  environment {
    variables = {
      CLOUDFRONT_ORIGIN_VERIFY_HEADER = var.cloudfront_origin_verify_header
      SECRET_NAME                     = aws_secretsmanager_secret.origin_verify.name
    }
  }
}

resource "aws_lambda_permission" "origin_verify_authorizer_invoke" {
  statement_id  = "AllowAPIGatewayAuthorizerInvoke"
  function_name = aws_lambda_function.origin_verify_authorizer.function_name
  action        = "lambda:InvokeFunction"
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.primary.execution_arn}/authorizers/${aws_apigatewayv2_authorizer.origin_verify.id}"
}

resource "aws_apigatewayv2_authorizer" "origin_verify" {
  api_id                            = aws_apigatewayv2_api.primary.id
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = aws_lambda_function.origin_verify_authorizer.invoke_arn
  identity_sources                  = ["$request.header.${var.cloudfront_origin_verify_header}"]
  name                              = "origin-verify-authorizer"
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
}

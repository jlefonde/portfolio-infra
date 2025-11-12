resource "aws_cloudwatch_log_group" "lambda" {
  count = var.lambda_config.enable_log ? 1 : 0

  name              = "/aws/lambda/${var.lambda_name}"
  retention_in_days = var.lambda_config.log_retention
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

data "aws_iam_policy_document" "lambda" {
  dynamic "statement" {
    for_each = var.lambda_config.policy_statements

    content {
      sid       = statement.value.sid
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources
    }
  }

  dynamic "statement" {
    for_each = var.lambda_config.enable_log == true ? [1] : []

    content {
      sid    = "AllowLambdaServiceWriteLogs"
      effect = "Allow"

      actions = [
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]

      resources = ["${aws_cloudwatch_log_group.lambda[0].arn}:*"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "lamdba-${var.lambda_name}-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy" "lambda" {
  role   = aws_iam_role.lambda.name
  policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_s3_object" "lambda" {
  count = var.lambda_config.use_s3 ? 1 : 0

  bucket      = var.lambda_config.s3_bucket
  key         = var.lambda_config.s3_key
  source      = var.lambda_config.source_file
  source_hash = filebase64sha256(var.lambda_config.source_file)
}

resource "aws_lambda_function" "lambda" {
  function_name = var.lambda_name
  role          = aws_iam_role.lambda.arn
  publish       = var.lambda_config.publish

  filename         = !var.lambda_config.use_s3 ? var.lambda_config.source_file : null
  source_code_hash = !var.lambda_config.use_s3 ? filebase64sha256(var.lambda_config.source_file) : null
  s3_key           = var.lambda_config.use_s3 ? aws_s3_object.lambda[0].key : null
  s3_bucket        = var.lambda_config.use_s3 ? var.lambda_config.s3_bucket : null

  handler = var.lambda_config.handler
  runtime = var.lambda_config.runtime

  environment {
    variables = var.lambda_config.environment
  }

  depends_on = [aws_s3_object.lambda]
  lifecycle {
    ignore_changes = [s3_key]
  }
}

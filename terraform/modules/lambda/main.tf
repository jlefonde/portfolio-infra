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

resource "aws_iam_policy" "lambda" {
  name   = "lambda-${var.lambda_name}-policy"
  policy = data.aws_iam_policy_document.lambda.json
}

resource "aws_iam_role_policy_attachment" "lambda" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda.arn
}

data "archive_file" "lambda" {
  type        = "zip"
  source_file = "${var.lambda_config.bootstrap_dir}/bootstrap"
  output_path = "${var.lambda_config.bootstrap_dir}/${var.lambda_name}.zip"
}

resource "aws_lambda_function" "lambda" {
  function_name = var.lambda_name
  role          = aws_iam_role.lambda.arn
  publish       = true

  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  handler          = var.lambda_config.handler
  runtime          = var.lambda_config.runtime

  environment {
    variables = var.lambda_config.environment
  }
}

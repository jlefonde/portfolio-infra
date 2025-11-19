output "lambda_function_arn" {
  description = "ARN of the Lambda function"
  value       = var.lambda_config.ignore_source_code_changes ? aws_lambda_function.lambda_ignore_changes[0].arn : aws_lambda_function.lambda[0].arn
}

output "lambda_function_name" {
  description = "Name of the Lambda function"
  value       = var.lambda_config.ignore_source_code_changes ? aws_lambda_function.lambda_ignore_changes[0].function_name : aws_lambda_function.lambda[0].function_name
}

output "lambda_function_invoke_arn" {
  description = "Invoke ARN of the Lambda function"
  value       = var.lambda_config.ignore_source_code_changes ? aws_lambda_function.lambda_ignore_changes[0].invoke_arn : aws_lambda_function.lambda[0].invoke_arn
}

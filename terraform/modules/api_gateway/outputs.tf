output "api_endpoint" {
  value = aws_apigatewayv2_api.primary.api_endpoint
}

output "api_execution_arn" {
  value = aws_apigatewayv2_api.primary.execution_arn
}
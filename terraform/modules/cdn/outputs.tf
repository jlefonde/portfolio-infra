output "distribution_arn" {
  value = aws_cloudfront_distribution.main.arn
}

output "distribution_id" {
  value = aws_cloudfront_distribution.main.id
}

output "backend_origin_id" {
  value = local.backend_origin_id
}

output "origin_verify_header" {
  value = local.cloudfront_origin_verify_header
}
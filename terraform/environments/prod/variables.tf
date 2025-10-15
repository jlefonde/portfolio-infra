variable "project_name" {
  description = "The project name"
  type        = string
}

variable "region" {
  description = "The AWS region where resources will be deployed (e.g., eu-central-1, us-east-1)"
  type        = string
}

variable "zone_name" {
  description = "The Route53 zone name"
  type        = string
}

variable "domain_name" {
  description = "The root domain name for the frontend website"
  type        = string
}

variable "acm_wildcard" {
  description = "The wildcard domain name for the ACM certificate"
  type        = string
}

variable "environment" {
  description = "The deployment environment (e.g., dev, staging, prod)"
  type        = string
}

variable "frontend_origin_id" {
  description = "Frontend origin ID for CloudFront distribution"
  type        = string
}

variable "backend_origin_id" {
  description = "Backend origin ID for CloudFront distribution"
  type        = string
}

variable "cloudfront_origin_verify_header" {
  description = "X-Origin-Verify header for CloudFront's API Gateway origin"
  type        = string
}

variable "origin_verify_rotation" {
  description = "Number of days between automatic scheduled secret rotation"
  type        = number
}

variable "lambda_log_retention" {
  description = "Number of days to retain log events for lambda"
  type        = number
}

# See: https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/using-managed-cache-policies.html
variable "cloudfront_cache_policy_ids" {
  description = "Number of days to retain log events for lambda"
  type = map(string)
  default = {
    caching_disabled  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    caching_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  }
}

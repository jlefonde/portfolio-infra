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
  description = "Origin ID for CloudFront distribution"
  type        = string
}

variable "cloudfront_min_ttl" {
  description = "Minimum TTL for CloudFront's default cache behavior"
  type        = number
}

variable "cloudfront_default_ttl" {
  description = "Default TTL for CloudFront's default cache behavior"
  type        = number
}

variable "cloudfront_max_ttl" {
  description = "Maximum TTL for CloudFront's default cache behavior"
  type        = number
}

variable "lambda_log_retention" {
  description = "Number of days to retain log events for lambda"
  type        = number
}

variable "dynamodb_tables" {
  description = "Configuration for DynamoDB tables"
  type = map(object({
    hash_key  = string
    range_key = optional(string)

    billing_mode   = string
    read_capacity  = optional(number)
    write_capacity = optional(number)

    attributes = list(object({
      name = string
      type = string
    }))

    global_secondary_indexes = optional(list(object({
      name            = string
      hash_key        = string
      range_key       = optional(string)
      projection_type = string
    })))
  }))

  default = {}
}

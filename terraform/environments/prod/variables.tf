variable "region" {
  description = "The AWS region where resources will be deployed (e.g., eu-central-1, us-east-1)"
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
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

variable "frontend_repo" {
  description = "The path to frontend repo"
  type        = string
}

variable "backend_repo" {
  description = "The path to backend repo"
  type        = string
}

variable "infra_repo" {
  description = "The path to infra repo"
  type        = string
}

variable "cloudfront_frontend_origin_cache_policy" {
  description = "The Cloudfront's frontend origin cache policy"
  type        = string
}

variable "cloudfront_backend_origin_cache_policy" {
  description = "The Cloudfront's backend origin cache policy"
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

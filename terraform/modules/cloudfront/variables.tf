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

variable "cloudfront_origin_verify_secret" {
  description = "The origin-verify secret value"
  type        = string
  sensitive   = true
}

variable "api_gateway_endpoint" {
  description = "The API Gateway endpoint"
  type        = string
}

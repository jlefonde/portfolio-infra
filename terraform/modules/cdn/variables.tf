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

variable "frontend_origin_cache_policy" {
  description = "The frontend origin cache policy"
  type        = string
}

variable "backend_origin_cache_policy" {
  description = "The backend origin cache policy"
  type        = string
}

variable "origin_verify_header_value" {
  description = "The request origin-verify header value for the API authorizer"
  type        = string
  sensitive   = true
}

variable "api_gateway_endpoint" {
  description = "The API Gateway endpoint"
  type        = string
}

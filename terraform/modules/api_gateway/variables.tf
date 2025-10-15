variable "api_name" {
  type    = string
  default = ""
}

variable "api_description" {
  type    = string
  default = null
}

variable "api_protocol_type" {
  type    = string
  default = "HTTP"
}

variable "api_ip_address_type" {
  type    = string
  default = null
}

variable "authorizers" {
  description = "Map of API gateway authorizers to create"
  type = map(object({
    name                              = optional(string)
    authorizer_uri                    = optional(string)
    authorizer_type                   = optional(string, "REQUEST")
    authorizer_payload_format_version = optional(string)
    identity_sources                  = optional(list(string))
    enable_simple_responses           = optional(bool)
  }))
}

variable "routes" {
  description = "Map of API gateway routes with integrations"
  type = map(object({
    authorizer_key     = optional(string)
    authorization_type = optional(string)
    integration = object({
      uri                    = optional(string)
      type                   = optional(string, "AWS_PROXY")
      method                 = optional(string)
      payload_format_version = optional(string)
      timeout_milliseconds   = optional(number)
    })
  }))
  default = {}
}

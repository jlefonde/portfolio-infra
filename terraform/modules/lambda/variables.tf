variable "lambda_name" {
  type = string
}

variable "lambda_config" {
  type = object({
    handler       = string
    runtime       = string
    bootstrap_dir = string
    environment   = optional(map(string), {})
    publish       = optional(bool, false)
    enable_log    = optional(bool, true)
    log_retention = optional(number, 7)

    policy_statements = optional(list(object({
      sid       = optional(string)
      effect    = optional(string, "Allow")
      actions   = optional(set(string), [])
      resources = optional(set(string), [])
    })), [])
  })
}

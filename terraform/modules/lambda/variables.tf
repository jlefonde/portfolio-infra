variable "lambda_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "lambda_config" {
  description = "Configuration for the Lambda function"
  type = object({
    handler                    = string
    runtime                    = string
    source_file                = string
    environment                = optional(map(string), {})
    publish                    = optional(bool, false)
    use_s3                     = optional(bool, false)
    s3_bucket                  = optional(string)
    s3_key                     = optional(string)
    enable_log                 = optional(bool, true)
    log_retention              = optional(number, 7)

    policy_statements = optional(list(object({
      sid       = optional(string)
      effect    = optional(string, "Allow")
      actions   = optional(set(string), [])
      resources = optional(set(string), [])
    })), [])
  })
}

variable "table_name" {
  description = "Name of the DynamoDB table"
  type        = string
}

variable "table_config" {
  description = "Configuration for DynamoDB table"
  type = object({
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
  })
}

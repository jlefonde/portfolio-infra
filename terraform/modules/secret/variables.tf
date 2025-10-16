variable "secret_name" {
  type = string
}

variable "secret_description" {
  type = string
}

variable "secret_config" {
  type = object({
    exclude_characters         = optional(string)
    exclude_lowercase          = optional(bool)
    exclude_numbers            = optional(bool)
    exclude_punctuation        = optional(bool)
    exclude_uppercase          = optional(bool)
    include_space              = optional(bool)
    password_length            = optional(number)
    require_each_included_type = optional(bool)
  })
}

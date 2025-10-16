resource "aws_secretsmanager_secret" "this" {
  name        = var.secret_name
  description = var.secret_description
}

data "aws_secretsmanager_random_password" "this" {
  exclude_characters         = var.secret_config.exclude_characters
  exclude_lowercase          = var.secret_config.exclude_lowercase
  exclude_numbers            = var.secret_config.exclude_numbers
  exclude_punctuation        = var.secret_config.exclude_punctuation
  exclude_uppercase          = var.secret_config.exclude_uppercase
  include_space              = var.secret_config.include_space
  password_length            = var.secret_config.password_length
  require_each_included_type = var.secret_config.require_each_included_type
}

resource "aws_secretsmanager_secret_version" "this" { 
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = data.aws_secretsmanager_random_password.this.random_password

  lifecycle {
    ignore_changes = [secret_string]
  }
}

output "secret_arn" {
  value = aws_secretsmanager_secret.this.arn
}

output "secret_id" {
  value = aws_secretsmanager_secret.this.id
}

output "secret_string" {
  value     = aws_secretsmanager_secret_version.this.secret_string
  sensitive = true
}

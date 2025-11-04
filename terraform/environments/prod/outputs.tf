output "oidc_frontend_role_arn" {
  value = aws_iam_role.oidc_frontend.arn
}

output "route53_name_servers" {
  value = aws_route53_zone.this.name_servers
}

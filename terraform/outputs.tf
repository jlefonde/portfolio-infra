output "oidc_role_arn" {
  value = [for k, v in aws_iam_role.oidc : v.arn]
}

output "route53_name_servers" {
  value = tolist(aws_route53_zone.this.name_servers)
}

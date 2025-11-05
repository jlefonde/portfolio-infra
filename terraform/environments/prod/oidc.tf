locals {
  oidc_roles = {
    frontend = {
      subject             = "repo:${var.frontend_repo}:environment:${var.environment}"
      managed_policy_arns = []
      inline_policy       = data.aws_iam_policy_document.oidc_frontend.json
    }
    backend = {
      subject             = "repo:${var.backend_repo}:environment:${var.environment}"
      managed_policy_arns = []
      inline_policy       = data.aws_iam_policy_document.oidc_backend.json
    }
    infra = {
      subject             = "repo:${var.infra_repo}:environment:${var.environment}"
      managed_policy_arns = ["arn:aws:iam::aws:policy/PowerUserAccess"]
      inline_policy       = null
    }
    infra-read-only = {
      subject             = "repo:${var.infra_repo}:ref:refs/heads/main"
      managed_policy_arns = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
      inline_policy       = null
    }
  }
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "oidc_assume_role" {
  for_each = local.oidc_roles

  statement {
    sid    = "AllowWebIdentityAssumeRole"
    effect = "Allow"

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }

    actions = ["sts:AssumeRoleWithWebIdentity"]

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = [each.value.subject]
    }
  }
}

resource "aws_iam_role" "oidc" {
  for_each = local.oidc_roles

  name               = "oidc-${each.key}-role"
  assume_role_policy = data.aws_iam_policy_document.oidc_assume_role[each.key].json
}

data "aws_iam_policy_document" "oidc_frontend" {
  statement {
    sid    = "AllowS3Sync"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [
      module.cdn.frontend_bucket_arn,
      "${module.cdn.frontend_bucket_arn}/*"
    ]
  }

  statement {
    sid    = "AllowSSMParameterRead"
    effect = "Allow"

    actions = ["ssm:GetParameter"]

    resources = [
      aws_ssm_parameter.frontend_bucket_name.arn,
      aws_ssm_parameter.distribution_id.arn
    ]
  }

  statement {
    sid    = "AllowCreateCloudfrontInvalidation"
    effect = "Allow"

    actions = ["cloudfront:CreateInvalidation"]

    resources = [module.cdn.distribution_arn]
  }
}

data "aws_iam_policy_document" "oidc_backend" {
  statement {
    sid    = "AllowS3Sync"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:PutObject",
      "s3:DeleteObject"
    ]

    resources = [
      aws_s3_bucket.backend.arn,
      "${aws_s3_bucket.backend.arn}/*"
    ]
  }

  statement {
    sid    = "AllowSSMParameterRead"
    effect = "Allow"

    actions = ["ssm:GetParameter"]

    resources = [
      aws_ssm_parameter.backend_bucket_name.arn
    ]
  }
}

resource "aws_iam_role_policy" "this" {
  for_each = {
    for role_key, role_value in local.oidc_roles : role_key => role_value
    if role_value.inline_policy != null
  }

  role   = aws_iam_role.oidc[each.key].name
  policy = each.value.inline_policy
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = {
    for pair in flatten([
      for role_key, role_value in local.oidc_roles : [
        for policy_arn in role_value.managed_policy_arns : {
          role       = role_key
          policy_arn = policy_arn
        }
      ]
    ]) : "${pair.role}-${basename(pair.policy_arn)}" => pair
  }

  role       = aws_iam_role.oidc[each.value.role].name
  policy_arn = each.value.policy_arn
}

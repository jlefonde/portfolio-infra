locals {
  oidc_roles = {
    frontend = {
      subject = "repo:${var.frontend_repo}:environment:${var.environment}"
    }
    backend = {
      subject = "repo:${var.backend_repo}:environment:${var.environment}"
    }
    infra = {
      subject = "repo:${var.infra_repo}:environment:${var.environment}"
    }
    infra-read-only = {
      subject = "repo:${var.infra_repo}:ref:refs/heads/main"
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

resource "aws_iam_policy" "oidc_frontend" {
  name   = "oidc-frontend-policy"
  policy = data.aws_iam_policy_document.oidc_frontend.json
}

resource "aws_iam_role_policy_attachment" "oidc_frontend" {
  role       = aws_iam_role.oidc["frontend"].name
  policy_arn = aws_iam_policy.oidc_frontend.arn
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

resource "aws_iam_policy" "oidc_backend" {
  name   = "oidc-backend-policy"
  policy = data.aws_iam_policy_document.oidc_backend.json
}

resource "aws_iam_role_policy_attachment" "oidc_backend" {
  role       = aws_iam_role.oidc["backend"].name
  policy_arn = aws_iam_policy.oidc_backend.arn
}

data "aws_iam_policy" "power_user_access" {
  name = "PowerUserAccess"
}

resource "aws_iam_role_policy_attachment" "oidc_infra" {
  role       = aws_iam_role.oidc["infra"].name
  policy_arn = data.aws_iam_policy.power_user_access.arn
}

data "aws_iam_policy" "read_only_access" {
  name = "ReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "oidc_infra_read_only" {
  role       = aws_iam_role.oidc["infra-read-only"].name
  policy_arn = data.aws_iam_policy.read_only_access.arn
}

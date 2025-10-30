resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

data "aws_iam_policy_document" "oidc_assume_role" {
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
      values   = ["repo:${var.frontend_repo}:ref:refs/heads/${local.repo_branch[var.environment]}"]
    }
  }
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

resource "aws_iam_role_policy_attachment" "name" {
  role       = aws_iam_role.oidc_frontend.name
  policy_arn = aws_iam_policy.oidc_frontend.arn
}

resource "aws_iam_role" "oidc_frontend" {
  name               = "oidc-frontend-role"
  assume_role_policy = data.aws_iam_policy_document.oidc_assume_role.json
}

output "oidc_frontend_role_arn" {
  value = aws_iam_role.oidc_frontend.arn
}

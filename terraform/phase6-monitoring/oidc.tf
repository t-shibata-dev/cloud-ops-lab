# GitHub Actions 用 OIDC Provider
resource "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"

  client_id_list = ["sts.amazonaws.com"]

  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# GitHub Actions が引き受ける IAM Role
resource "aws_iam_role" "github_actions" {
  name = "github-actions-terraform-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:t-shibata-dev/cloud-ops-lab:*"
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

# Terraform 操作に必要な権限
resource "aws_iam_role_policy" "github_actions" {
  name = "github-actions-terraform-policy"
  role = aws_iam_role.github_actions.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sns:*",
          "lambda:*",
          "events:*",
          "iam:*",
          "s3:*",
          "logs:*"
        ]
        Resource = "*"
      }
    ]
  })
}

# outputs に Role ARN を追加
output "github_actions_role_arn" {
  value = aws_iam_role.github_actions.arn
}

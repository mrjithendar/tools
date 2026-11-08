# Role that the miniKube repository's .github/workflows/create-mk-infrastructure.yml assumes through GitHub OIDC to read and write the
# minikube-infrastructure/ state (both now in mrjithendar/miniKube). Only jobs in that repository's GitHub environment "mk4" can assume it
# (that environment allows master only), and it reaches nothing but that one state object and its lock.
# The GitHub OIDC provider already exists in the account; its ARN is fixed, so it is built, not looked up.
locals {
  minikube_state_bucket = "jithendardharmapuri"
  minikube_state_key    = "terraform/minikube-mk4.tfstate"
}

resource "aws_iam_role" "github_minikube_terraform" {
  name                 = "github-tools-minikube-terraform"
  description          = "GitHub Actions (mrjithendar/miniKube, environment mk4): minikube-infrastructure state only"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::${data.aws_caller_identity.bedrock.account_id}:oidc-provider/token.actions.githubusercontent.com" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:mrjithendar/miniKube:environment:mk4"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "github_minikube_terraform_state" {
  name = "minikube-terraform-state"
  role = aws_iam_role.github_minikube_terraform.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = "arn:aws:s3:::${local.minikube_state_bucket}"
        Condition = { StringLike = { "s3:prefix" = ["${local.minikube_state_key}*"] } }
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "arn:aws:s3:::${local.minikube_state_bucket}/${local.minikube_state_key}"
      },
      {
        # use_lockfile = true: the S3 backend locks with "<key>.tflock".
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::${local.minikube_state_bucket}/${local.minikube_state_key}.tflock"
      },
    ]
  })
}

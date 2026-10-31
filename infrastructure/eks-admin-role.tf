# Cluster administrator role, granted access through eks_admin_principal_arns in the tfvars. The trust policy
# lets IAM users and roles in this account assume it if they also hold sts:AssumeRole; the root user cannot.
resource "aws_iam_role" "eks_admin" {
  count                = var.eks_enabled ? 1 : 0
  name                 = "${local.eks_name}-eks-admin"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.bedrock.account_id}:root" }
    }]
  })
  tags = local.common_tags
}

# Needed by `aws eks update-kubeconfig`; Kubernetes permissions come from the EKS access entry.
resource "aws_iam_role_policy" "eks_admin" {
  count = var.eks_enabled ? 1 : 0
  name  = "describe-cluster"
  role  = aws_iam_role.eks_admin[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "eks:DescribeCluster"
      Resource = aws_eks_cluster.main[0].arn
    }]
  })
}

output "eks_admin_role_arn" {
  value = try(aws_iam_role.eks_admin[0].arn, null)
}

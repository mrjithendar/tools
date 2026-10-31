resource "aws_cloudwatch_log_group" "eks" {
  count             = var.eks_enabled ? 1 : 0
  name              = "/aws/eks/${local.eks_name}/cluster"
  retention_in_days = 30
  tags              = local.common_tags
}

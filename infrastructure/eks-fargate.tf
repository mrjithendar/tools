# Pods in eks_fargate_namespaces run on Fargate instead of the node group. EKS Fargate is x86 only, so these
# namespaces need linux/amd64 images; the arm64 service images stay on the nodes. Only private subnets are accepted.
resource "aws_eks_fargate_profile" "main" {
  count                  = local.eks_fargate_enabled ? 1 : 0
  cluster_name           = aws_eks_cluster.main[0].name
  fargate_profile_name   = "fargate"
  pod_execution_role_arn = aws_iam_role.eks_fargate[0].arn
  subnet_ids             = local.privateSubnets
  dynamic "selector" {
    for_each = var.eks_fargate_namespaces
    content {
      namespace = selector.value
    }
  }
  tags       = local.common_tags
  depends_on = [aws_iam_role_policy_attachment.eks_fargate]
}

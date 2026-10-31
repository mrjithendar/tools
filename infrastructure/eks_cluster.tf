# Opt-in keeps existing VPC/ECR/SES deployments unchanged until EKS is configured.
resource "aws_eks_cluster" "main" {
  count                     = var.eks_enabled ? 1 : 0
  name                      = local.eks_name
  role_arn                  = aws_iam_role.eks_cluster[0].arn
  version                   = var.eks_version
  enabled_cluster_log_types = [
    "api", "audit", "authenticator", "controllerManager", "scheduler"
    ]
  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = false
  }
  upgrade_policy { support_type = "STANDARD" }
  vpc_config {
    subnet_ids              = local.privateSubnets
    endpoint_private_access = true
    endpoint_public_access  = length(var.eks_public_access_cidrs) > 0
    public_access_cidrs     = length(var.eks_public_access_cidrs) > 0 ? var.eks_public_access_cidrs : null
  }
  lifecycle {
    precondition {
      condition     = length(var.eks_admin_principal_arns) > 0
      error_message = "Set at least one eks_admin_principal_arns entry before enabling EKS."
    }
  }
  tags       = local.common_tags
  depends_on = [aws_iam_role_policy_attachment.eks_cluster, aws_cloudwatch_log_group.eks]
}
resource "aws_eks_access_entry" "admins" {
  for_each      = var.eks_enabled ? var.eks_admin_principal_arns : toset([])
  cluster_name  = aws_eks_cluster.main[0].name
  principal_arn = each.value
  type          = "STANDARD"
  depends_on    = [aws_iam_role.eks_admin] # the principal must exist first
}
resource "aws_eks_access_policy_association" "admins" {
  for_each      = aws_eks_access_entry.admins
  cluster_name  = each.value.cluster_name
  principal_arn = each.value.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  access_scope { type = "cluster" }
}

resource "aws_vpc_security_group_ingress_rule" "eks_private_api" {
  for_each          = var.eks_enabled ? var.eks_private_access_cidrs : toset([])
  security_group_id = aws_eks_cluster.main[0].vpc_config[0].cluster_security_group_id
  description       = "Private EKS API access for connected administration network"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

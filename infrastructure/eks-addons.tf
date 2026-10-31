# AWS resolves the default compatible build for this Kubernetes version at plan time.
data "aws_eks_addon_version" "core" {
  for_each           = var.eks_enabled ? toset(["vpc-cni", "coredns", "kube-proxy", "eks-pod-identity-agent"]) : toset([])
  addon_name         = each.key
  kubernetes_version = var.eks_version
  most_recent        = false
}
resource "aws_eks_addon" "core" {
  for_each                    = data.aws_eks_addon_version.core
  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = each.key
  addon_version               = each.value.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on                  = [aws_eks_node_group.main]
}

# Monitoring and certificate add-ons. Pods on Fargate are not covered: the agents here run as DaemonSets.
data "aws_eks_addon_version" "observability" {
  for_each           = var.eks_enabled ? toset(concat(local.eks_observability_addons, ["adot"])) : toset([])
  addon_name         = each.key
  kubernetes_version = var.eks_version
  most_recent        = false
}
resource "aws_eks_addon" "observability" {
  for_each                    = { for name, addon in data.aws_eks_addon_version.observability : name => addon if name != "adot" }
  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = each.key
  addon_version               = each.value.version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on                  = [aws_eks_addon.core]
}
# Installs the ADOT operator only; collectors come from OpenTelemetryCollector resources.
# Its webhooks need cert-manager running first.
resource "aws_eks_addon" "adot" {
  count                       = var.eks_enabled ? 1 : 0
  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = "adot"
  addon_version               = data.aws_eks_addon_version.observability["adot"].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  depends_on                  = [aws_eks_addon.observability]
}

# Provisions EBS volumes for PersistentVolumeClaims and creates a default StorageClass: the cluster's own gp2 class is
# not the default, so a PVC naming no class would stay Pending. EBS volumes cannot be mounted on Fargate.
data "aws_eks_addon_version" "ebs_csi" {
  count              = var.eks_enabled ? 1 : 0
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = var.eks_version
  most_recent        = false
}
resource "aws_eks_addon" "ebs_csi" {
  count                       = var.eks_enabled ? 1 : 0
  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = "aws-ebs-csi-driver"
  addon_version               = data.aws_eks_addon_version.ebs_csi[0].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  configuration_values        = jsonencode({ defaultStorageClass = { enabled = true } })
  pod_identity_association {
    role_arn        = aws_iam_role.eks_ebs_csi[0].arn
    service_account = "ebs-csi-controller-sa"
  }
  # Pod Identity needs the agent from aws_eks_addon.core.
  depends_on = [aws_eks_addon.core, aws_iam_role_policy_attachment.eks_ebs_csi]
}
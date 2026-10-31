# Container Network Observability: the service map and flow table on the cluster's Network tab in the EKS console.
# The agent is a DaemonSet, so it sees node pods only, not Fargate. The scope covers the whole account in this region.
resource "aws_networkflowmonitor_scope" "main" {
  count = local.eks_network_observability_enabled ? 1 : 0
  target {
    region = var.aws_region
    target_identifier {
      target_type = "ACCOUNT"
      target_id {
        account_id = data.aws_caller_identity.bedrock.account_id
      }
    }
  }
  tags = local.common_tags
}
resource "aws_networkflowmonitor_monitor" "main" {
  count        = local.eks_network_observability_enabled ? 1 : 0
  monitor_name = "${local.eks_name}-monitor"
  scope_arn    = aws_networkflowmonitor_scope.main[0].scope_arn
  local_resource {
    type       = "AWS::EKS::Cluster"
    identifier = aws_eks_cluster.main[0].arn
  }
  remote_resource {
    type       = "AWS::Region"
    identifier = var.aws_region
  }
  tags = local.common_tags
}
data "aws_eks_addon_version" "network_flow_monitor" {
  count              = local.eks_network_observability_enabled ? 1 : 0
  addon_name         = "aws-network-flow-monitoring-agent"
  kubernetes_version = var.eks_version
  most_recent        = false
}
resource "aws_eks_addon" "network_flow_monitor" {
  count                       = local.eks_network_observability_enabled ? 1 : 0
  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = "aws-network-flow-monitoring-agent"
  addon_version               = data.aws_eks_addon_version.network_flow_monitor[0].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  pod_identity_association {
    role_arn        = aws_iam_role.eks_network_flow_monitor[0].arn
    service_account = "aws-network-flow-monitor-agent-service-account"
  }
  # Pod Identity needs the agent from aws_eks_addon.core.
  depends_on = [aws_eks_addon.core, aws_iam_role_policy_attachment.eks_network_flow_monitor]
}

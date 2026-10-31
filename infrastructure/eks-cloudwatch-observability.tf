# One add-on provides Application Signals (APM), Container Insights and OTel Container Insights. Running both Container
# Insights pipelines publishes the metrics twice, and each is billed. The add-on ships its own node-exporter,
# kube-state-metrics and Fluent Bit alongside the community add-ons in eks-addons.tf.
data "aws_eks_addon_version" "cloudwatch_observability" {
  count              = local.eks_cloudwatch_observability_enabled ? 1 : 0
  addon_name         = "amazon-cloudwatch-observability"
  kubernetes_version = var.eks_version
  most_recent        = false
}
resource "aws_eks_addon" "cloudwatch_observability" {
  count                       = local.eks_cloudwatch_observability_enabled ? 1 : 0
  cluster_name                = aws_eks_cluster.main[0].name
  addon_name                  = "amazon-cloudwatch-observability"
  addon_version               = data.aws_eks_addon_version.cloudwatch_observability[0].version
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  configuration_values = jsonencode({
    applicationSignals    = { enabled = true }
    containerInsights     = { enabled = true }
    otelContainerInsights = { enabled = true }
    # The 256m default on each is too much for 2 vCPU nodes.
    nodeExporter = {
      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { cpu = "250m", memory = "128Mi" }
      }
    }
    kubeStateMetrics = {
      resources = {
        requests = { cpu = "50m", memory = "64Mi" }
        limits   = { cpu = "250m", memory = "256Mi" }
      }
    }
  })
  pod_identity_association {
    role_arn        = aws_iam_role.eks_cloudwatch_observability[0].arn
    service_account = "cloudwatch-agent"
  }
  depends_on = [
    aws_eks_addon.core,
    aws_eks_addon.observability,
    aws_iam_role_policy_attachment.eks_cloudwatch_observability,
    aws_iam_service_linked_role.application_signals,
  ]
}

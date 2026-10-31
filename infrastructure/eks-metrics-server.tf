# Backs `kubectl top` and the Horizontal Pod Autoscaler. Same chart version as argocd/metrics-server.yaml;
# unlike Minikube, EKS kubelet certificates verify, so --kubelet-insecure-tls is not set.
resource "helm_release" "metrics_server" {
  count      = var.eks_enabled ? 1 : 0
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  version    = "3.14.0"
  namespace  = "kube-system"
  values = [yamlencode({
    replicas = 1
    resources = {
      requests = { cpu = "100m", memory = "128Mi" }
      limits   = { cpu = "300m", memory = "256Mi" }
    }
  })]
  depends_on = [aws_eks_node_group.main, aws_eks_addon.core]
}

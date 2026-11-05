# Argo CD itself. Values: deploy/minikube/argocd/values.yaml. Its public route is not part of the chart
# (deploy/minikube/argocd/kustomization.yaml today, Kong after the cutover).
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.10.5"
  values           = [file("${path.module}/../deploy/minikube/argocd/values.yaml")]

  # Adopts the objects of the earlier helm install (README.md: the stuck pending-install record
  # is removed first). The chart keeps its CRDs on uninstall, so Applications survive a reinstall.
  take_ownership = true
  wait           = true
  timeout        = var.helm_timeout
}

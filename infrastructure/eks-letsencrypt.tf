# letsencrypt-staging and letsencrypt-prod ClusterIssuers, from the same chart mk4 uses. The domain points at mk4 and EKS
# has no ingress controller, so HTTP-01 cannot reach this cluster: they solve DNS-01 through Cloudflare instead.
# The API token is a Secret created by hand so it stays out of Terraform state: see minikube/cert-manager/README.md.
resource "helm_release" "letsencrypt_issuers" {
  count     = local.eks_letsencrypt_enabled ? 1 : 0
  name      = "letsencrypt-issuers"
  chart     = "${path.module}/../minikube/cert-manager/issuers"
  namespace = "cert-manager"
  values = [yamlencode({
    dns01 = {
      zone           = var.eks_letsencrypt_dns_zone
      apiTokenSecret = "cloudflare-api-token"
      apiTokenKey    = "api-token"
    }
  })]
  depends_on = [aws_eks_addon.observability]
}

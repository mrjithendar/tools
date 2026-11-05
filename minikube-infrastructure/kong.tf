# Kong Gateway OSS 3.9.4 in database mode, with its PostgreSQL: the local chart deploy/minikube/kong
# (plain manifests in templates/, no values). Kong's own entities (routes, plugins, consumers)
# are in Kong's database, never in this release (docs/kong/02-architecture.md).
#
# Off until the cutover window (docs/kong/06-cutover-runbook.md): set kong_enabled = true in
# vars/mk4.tfvars. Secret kong/kong-postgres must exist first
# (bash deploy/minikube/kong/create-secrets.sh); without it the pods cannot start and this
# release times out.
resource "helm_release" "kong" {
  count = var.kong_enabled ? 1 : 0

  name      = "kong"
  namespace = "kong"
  # create-secrets.sh creates the namespace together with the Secret.
  create_namespace = false
  chart            = "${path.module}/../deploy/minikube/kong"

  wait = true
  # PostgreSQL start, the bootstrap Job and Kong's migration check run one after another.
  timeout = 900

  # Kong's Certificates need cert-manager's CRDs and webhook.
  depends_on = [helm_release.cert_manager]
}

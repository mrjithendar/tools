# Mock provider only: no cluster is contacted. Run: terraform init -backend=false && terraform test
mock_provider "helm" {}

run "pinned_releases" {
  command = plan

  assert {
    condition = (
      helm_release.metrics_server.version == "3.14.0" &&
      helm_release.cert_manager.version == "v1.20.4" &&
      helm_release.argocd.version == "10.10.5"
    )
    error_message = "Chart versions must stay pinned to the versions the Argo CD catalog used."
  }

  assert {
    condition = (
      helm_release.metrics_server.namespace == "kube-system" &&
      helm_release.cert_manager.namespace == "cert-manager" &&
      helm_release.argocd.namespace == "argocd"
    )
    error_message = "Release namespaces must match the live installations."
  }

  assert {
    condition     = helm_release.metrics_server.take_ownership && helm_release.cert_manager.take_ownership && helm_release.argocd.take_ownership
    error_message = "Existing objects have no (usable) Helm release; the first apply must adopt them."
  }

  assert {
    condition     = length(helm_release.kong) == 0
    error_message = "Kong must stay off until the cutover sets kong_enabled."
  }
}

run "kong_in_cutover" {
  command = plan

  variables {
    kong_enabled = true
  }

  assert {
    condition = (
      helm_release.kong[0].namespace == "kong" &&
      !helm_release.kong[0].create_namespace &&
      endswith(helm_release.kong[0].chart, "/deploy/minikube/kong")
    )
    error_message = "Kong is the local chart in namespace kong; create-secrets.sh creates the namespace with the Secret."
  }
}

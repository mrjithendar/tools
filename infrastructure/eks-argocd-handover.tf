# These releases moved to Argo CD (eks-argocd/applications). destroy = false makes Terraform forget them: deleting the resources
# alone would uninstall them, and with the gateway Service the NLB. Delete this file and the helm provider once the
# applied state has no helm_release left; the order is in eks-argocd/RUNBOOK.md.
removed {
  from = helm_release.aws_load_balancer_controller
  lifecycle { destroy = false }
}
removed {
  from = helm_release.istio_base
  lifecycle { destroy = false }
}
removed {
  from = helm_release.istiod
  lifecycle { destroy = false }
}
removed {
  from = helm_release.istio_ingressgateway
  lifecycle { destroy = false }
}
removed {
  from = helm_release.metrics_server
  lifecycle { destroy = false }
}
removed {
  from = helm_release.letsencrypt_issuers
  lifecycle { destroy = false }
}
removed {
  from = helm_release.prometheus_agent
  lifecycle { destroy = false }
}

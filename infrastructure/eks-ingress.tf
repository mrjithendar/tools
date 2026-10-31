# Public entry for RoboShop: an internet-facing NLB in front of the Istio ingress gateway, with sidecar mesh mTLS behind
# it. Opt-in, because this workflow applies on push to master and the NLB is billed from the moment it exists. Gateway,
# routes, certificate, identities and policies are Argo CD resources in eks/; eks/RUNBOOK.md gives the order.
locals {
  istio_version = "1.30.7" # 1.31 charts are not published yet; 1.30 supports Kubernetes 1.32-1.36
}

resource "aws_iam_policy" "eks_load_balancer_controller" {
  count  = local.eks_ingress_enabled ? 1 : 0
  name   = "${local.eks_name}-load-balancer-controller"
  policy = file("${path.module}/policies/aws-load-balancer-controller-v3.6.2.json")
  tags   = local.common_tags
}
resource "aws_iam_role_policy_attachment" "eks_load_balancer_controller" {
  count      = local.eks_ingress_enabled ? 1 : 0
  role       = aws_iam_role.eks_load_balancer_controller[0].name
  policy_arn = aws_iam_policy.eks_load_balancer_controller[0].arn
}
resource "aws_eks_pod_identity_association" "load_balancer_controller" {
  count           = local.eks_ingress_enabled ? 1 : 0
  cluster_name    = aws_eks_cluster.main[0].name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.eks_load_balancer_controller[0].arn
  tags            = local.common_tags
}

resource "helm_release" "aws_load_balancer_controller" {
  count      = local.eks_ingress_enabled ? 1 : 0
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "3.6.2" # keep policies/ on the same tag
  namespace  = "kube-system"
  values = [yamlencode({
    clusterName  = aws_eks_cluster.main[0].name
    region       = var.aws_region
    vpcId        = aws_vpc.vpc.id # no IMDS lookup from the pod
    replicaCount = 2
    serviceAccount = {
      create = true
      name   = "aws-load-balancer-controller"
    }
    resources = {
      requests = { cpu = "50m", memory = "96Mi" }
      limits   = { memory = "256Mi" }
    }
    podDisruptionBudget = { maxUnavailable = 1 }
    keepTLSSecret       = true
    # Only a Service that asks for loadBalancerClass service.k8s.aws/nlb gets a load balancer.
    enableServiceMutatorWebhook = false
    createIngressClassResource  = false
    # ALB-only features; off so the controller never calls these APIs.
    enableShield = false
    enableWaf    = false
    enableWafv2  = false
    # Injects the target health readiness gate into the gateway pods: a rollout then waits for the new pod to pass NLB
    # health checks. Selected by name, because this namespace is created by Helm and carries no labels.
    webhookNamespaceSelectors = [{
      key      = "kubernetes.io/metadata.name"
      operator = "In"
      values   = ["istio-ingress"]
    }]
  })]
  # Pod Identity needs the agent from aws_eks_addon.core.
  depends_on = [aws_eks_addon.core, aws_eks_pod_identity_association.load_balancer_controller, aws_iam_role_policy_attachment.eks_load_balancer_controller]
}

resource "helm_release" "istio_base" {
  count            = local.eks_ingress_enabled ? 1 : 0
  name             = "istio-base"
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "base"
  version          = local.istio_version
  namespace        = "istio-system"
  create_namespace = true
  depends_on       = [aws_eks_addon.core]
}

resource "helm_release" "istiod" {
  count      = local.eks_ingress_enabled ? 1 : 0
  name       = "istiod"
  repository = "https://istio-release.storage.googleapis.com/charts"
  chart      = "istiod"
  version    = local.istio_version
  namespace  = "istio-system"
  values = [yamlencode({
    pilot = {
      autoscaleEnabled = false
      replicaCount     = 2 # the injection webhook fails closed, so a single istiod would block every new pod during a node drain
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "1Gi" }
      }
      env = {
        # The proxy starts before and stops after the application, including for init containers and Jobs.
        ENABLE_NATIVE_SIDECARS = "true"
      }
    }
    global = {
      proxy = {
        resources = {
          requests = { cpu = "20m", memory = "64Mi" }
          limits   = { memory = "256Mi" }
        }
      }
    }
    meshConfig = {
      # Mesh retries could replay a checkout or payment; the applications own idempotency.
      defaultHttpRetryPolicy = { attempts = 0 }
      defaultConfig          = { holdApplicationUntilProxyStarts = true }
    }
  })]
  depends_on = [helm_release.istio_base]
}

resource "helm_release" "istio_ingressgateway" {
  count            = local.eks_ingress_enabled ? 1 : 0
  name             = "istio-ingressgateway" # also the ServiceAccount in the workload identity AuthorizationPolicies match
  repository       = "https://istio-release.storage.googleapis.com/charts"
  chart            = "gateway"
  version          = local.istio_version
  namespace        = "istio-ingress"
  create_namespace = true
  timeout          = 900 # pods stay unready until the new NLB registers them
  values = [yamlencode({
    autoscaling = {
      enabled                        = true
      minReplicas                    = 2
      maxReplicas                    = 3
      targetCPUUtilizationPercentage = 80
    }
    podDisruptionBudget = { minAvailable = 1 }
    resources = {
      requests = { cpu = "100m", memory = "128Mi" }
      limits   = { memory = "512Mi" }
    }
    topologySpreadConstraints = [{
      maxSkew           = 1
      topologyKey       = "kubernetes.io/hostname"
      whenUnsatisfiable = "ScheduleAnyway"
      labelSelector     = { matchLabels = { istio = "ingressgateway" } }
    }]
    service = {
      type                          = "LoadBalancer"
      loadBalancerClass             = "service.k8s.aws/nlb"
      allocateLoadBalancerNodePorts = false # IP targets reach the pods directly
      # Becomes the NLB's frontend security group. Without it the NLB is open to the Internet.
      loadBalancerSourceRanges = var.eks_ingress_source_cidrs
      # HTTPS only: only Service ports become listeners, so the 15021 status port stays private and is used solely by
      # the health check. HTTP to HTTPS redirects stay on the edge in front of this NLB (minikube/roboshop).
      ports = [{ name = "https", port = 443, protocol = "TCP", targetPort = 443 }]
      annotations = {
        "service.beta.kubernetes.io/aws-load-balancer-name"            = "${local.eks_name}-ingress"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
        "service.beta.kubernetes.io/aws-load-balancer-subnets"         = join(",", local.publicSubnets)
        # TCP passthrough: no aws-load-balancer-ssl-cert, so TLS terminates on the gateway pods.
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-protocol"            = "http"
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-port"                = "15021"
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-path"                = "/healthz/ready"
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-interval"            = "10"
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-healthy-threshold"   = "2"
        "service.beta.kubernetes.io/aws-load-balancer-healthcheck-unhealthy-threshold" = "2"
        "service.beta.kubernetes.io/aws-load-balancer-attributes"                      = "load_balancing.cross_zone.enabled=true"
        "service.beta.kubernetes.io/aws-load-balancer-target-group-attributes"         = "deregistration_delay.timeout_seconds=30,preserve_client_ip.enabled=false"
        "service.beta.kubernetes.io/aws-load-balancer-additional-resource-tags"        = "Project=roboshop-ai,Environment=${var.environment},ManagedBy=aws-load-balancer-controller"
      }
    }
  })]
  lifecycle {
    precondition {
      condition     = length(var.eks_ingress_source_cidrs) > 0
      error_message = "Set eks_ingress_source_cidrs: an empty list opens the NLB to the Internet."
    }
  }
  # The controller must outlive this Service on destroy, or the NLB and its finalizer are left behind.
  depends_on = [helm_release.aws_load_balancer_controller, helm_release.istiod]
}

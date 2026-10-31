# Scrapes node-exporter and pushes to the Prometheus on mk4, which cannot reach these private nodes.
# Agent mode keeps only a short write-ahead buffer, so the data lives on mk4. Create the Secret first:
# observability/prometheus/README.md, "Metrics from EKS".
resource "helm_release" "prometheus_agent" {
  count            = local.eks_prometheus_agent_enabled ? 1 : 0
  name             = "prometheus-agent"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "prometheus"
  version          = "29.40.3"
  namespace        = "monitoring"
  create_namespace = true
  values = [yamlencode({
    alertmanager             = { enabled = false }
    kube-state-metrics       = { enabled = false }
    prometheus-node-exporter = { enabled = false }
    prometheus-pushgateway   = { enabled = false }
    server = {
      defaultFlagsOverride = ["--agent", "--config.file=/etc/config/prometheus.yml", "--storage.agent.path=/data"]
      persistentVolume     = { enabled = false }
      retention            = ""
      global = {
        scrape_interval = "30s"
        external_labels = { cluster = local.eks_name }
      }
      remoteWrite = [{
        url        = var.eks_prometheus_remote_write_url
        basic_auth = { username = "eks", password_file = "/etc/secrets/remote-write/password" }
      }]
      extraSecretMounts = [{
        name       = "remote-write-auth"
        mountPath  = "/etc/secrets/remote-write"
        secretName = "prometheus-remote-write-auth"
        readOnly   = true
      }]
      resources = {
        requests = { cpu = "50m", memory = "128Mi" }
        limits   = { cpu = "300m", memory = "256Mi" }
      }
    }
    # null drops the chart's default jobs, which would push every pod and node metric to mk4.
    scrapeConfigs = null
    serverFiles = {
      "prometheus.yml" = {
        rule_files = []
        scrape_configs = [{
          job_name = "eks-node-exporter"
          kubernetes_sd_configs = [{
            role       = "endpointslice"
            namespaces = { names = ["prometheus-node-exporter"] }
          }]
          relabel_configs = [
            {
              source_labels = ["__meta_kubernetes_service_name"]
              regex         = "prometheus-node-exporter"
              action        = "keep"
            },
            {
              source_labels = ["__meta_kubernetes_pod_node_name"]
              target_label  = "node"
            },
          ]
        }]
      }
    }
  })]
  depends_on = [aws_eks_addon.observability]
}

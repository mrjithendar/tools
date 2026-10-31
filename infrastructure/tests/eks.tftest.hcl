mock_provider "helm" {}

mock_provider "aws" {
  mock_data "aws_caller_identity" {
    defaults = { account_id = "123456789012" }
  }
  mock_data "aws_eks_addon_version" {
    defaults = { version = "v1.0.0-eksbuild.1" }
  }
  mock_data "aws_availability_zones" {
    defaults = { names = ["us-east-1a", "us-east-1b"] }
  }
}
variables {
  environment        = "test"
  availability_zones = ["us-east-1a", "us-east-1b"]
}
run "disabled_by_default" {
  command = plan
  assert {
    condition     = length(aws_eks_cluster.main) == 0
    error_message = "Existing network-only callers must not create EKS automatically."
  }
}
run "private_cluster" {
  command = plan
  variables {
    eks_enabled              = true
    eks_admin_principal_arns = ["arn:aws:iam::123456789012:role/admin"]
  }
  assert {
    condition     = aws_eks_cluster.main[0].vpc_config[0].endpoint_private_access && !aws_eks_cluster.main[0].vpc_config[0].endpoint_public_access
    error_message = "API must default to private-only."
  }
  assert {
    condition     = aws_eks_node_group.main[0].ami_type == "AL2023_ARM_64_STANDARD" && aws_eks_node_group.main[0].scaling_config[0].desired_size == 2
    error_message = "Use two AL2023 workers by default."
  }
  assert {
    condition     = length(aws_eks_access_entry.admins) == 1 && length(aws_eks_addon.core) == 4
    error_message = "Explicit admin access and all core add-ons must be configured."
  }
}
run "reject_world_open_api" {
  command = plan
  variables { eks_public_access_cidrs = ["0.0.0.0/0"] }
  expect_failures = [var.eks_public_access_cidrs]
}
run "reject_missing_admin" {
  command = plan
  variables { eks_enabled = true }
  expect_failures = [aws_eks_cluster.main]
}
run "connected_private_runner" {
  command = plan
  variables {
    eks_enabled              = true
    eks_admin_principal_arns = ["arn:aws:iam::123456789012:role/admin"]
    eks_private_access_cidrs = ["10.20.0.5/32"]
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.eks_private_api["10.20.0.5/32"].from_port == 443 && aws_vpc_security_group_ingress_rule.eks_private_api["10.20.0.5/32"].to_port == 443 && !aws_eks_cluster.main[0].vpc_config[0].endpoint_public_access
    error_message = "Private runner access must open only API TLS, without enabling the public endpoint."
  }
}
run "reject_sts_admin" {
  command = plan
  variables { eks_admin_principal_arns = ["arn:aws:sts::123456789012:assumed-role/admin/session"] }
  expect_failures = [var.eks_admin_principal_arns]
}
run "reject_world_open_private_api" {
  command = plan
  variables { eks_private_access_cidrs = ["0.0.0.0/0"] }
  expect_failures = [var.eks_private_access_cidrs]
}

run "fargate_off_by_default" {
  command = plan
  variables {
    eks_enabled              = true
    eks_admin_principal_arns = ["arn:aws:iam::123456789012:role/admin"]
  }
  assert {
    condition     = length(aws_eks_fargate_profile.main) == 0 && length(aws_iam_role.eks_fargate) == 0
    error_message = "A Fargate profile must be opt-in."
  }
}

run "fargate_namespace" {
  command = plan
  variables {
    eks_enabled              = true
    eks_admin_principal_arns = ["arn:aws:iam::123456789012:role/admin"]
    eks_fargate_namespaces   = ["fargate"]
  }
  assert {
    condition     = length(aws_eks_fargate_profile.main) == 1 && one(aws_eks_fargate_profile.main[0].selector).namespace == "fargate"
    error_message = "The profile must select the configured namespace."
  }
}

run "reject_six_fargate_namespaces" {
  command = plan
  variables {
    eks_fargate_namespaces = ["a", "b", "c", "d", "e", "f"]
  }
  expect_failures = [var.eks_fargate_namespaces]
}

run "network_observability_off_by_default" {
  command = plan
  variables {
    eks_enabled              = true
    eks_admin_principal_arns = ["arn:aws:iam::123456789012:role/admin"]
  }
  assert {
    condition     = length(aws_networkflowmonitor_monitor.main) == 0 && length(aws_eks_addon.network_flow_monitor) == 0
    error_message = "Network observability must be opt-in."
  }
}

run "network_observability_enabled" {
  command = plan
  variables {
    eks_enabled                       = true
    eks_admin_principal_arns          = ["arn:aws:iam::123456789012:role/admin"]
    eks_network_observability_enabled = true
  }
  assert {
    condition     = length(aws_networkflowmonitor_scope.main) == 1 && length(aws_networkflowmonitor_monitor.main) == 1 && one(aws_eks_addon.network_flow_monitor[0].pod_identity_association).service_account == "aws-network-flow-monitor-agent-service-account"
    error_message = "The scope, monitor and agent must be created together, with the agent's service account."
  }
}

run "network_observability_needs_eks" {
  command = plan
  variables {
    eks_network_observability_enabled = true
  }
  assert {
    condition     = length(aws_networkflowmonitor_scope.main) == 0
    error_message = "Network observability must not be created without a cluster."
  }
}

run "observability_addons" {
  command = plan
  variables {
    eks_enabled              = true
    eks_admin_principal_arns = ["arn:aws:iam::123456789012:role/admin"]
  }
  assert {
    condition     = toset(keys(aws_eks_addon.observability)) == toset(["cert-manager", "eks-node-monitoring-agent", "fluent-bit", "kube-state-metrics", "prometheus-node-exporter"]) && length(aws_eks_addon.adot) == 1
    error_message = "All observability add-ons must install with the cluster; adot is separate so it can wait for cert-manager."
  }
}

run "prometheus_agent_off_by_default" {
  command = plan
  variables {
    eks_enabled              = true
    eks_admin_principal_arns = ["arn:aws:iam::123456789012:role/admin"]
  }
  assert {
    condition     = length(helm_release.prometheus_agent) == 0
    error_message = "The agent must be opt-in."
  }
}

run "prometheus_agent_pushes_remotely" {
  command = plan
  variables {
    eks_enabled                     = true
    eks_admin_principal_arns        = ["arn:aws:iam::123456789012:role/admin"]
    eks_prometheus_remote_write_url = "https://example.com/api/v1/write"
  }
  assert {
    condition     = length(helm_release.prometheus_agent) == 1
    error_message = "A remote write URL must install the agent."
  }
}

run "reject_plain_http_remote_write" {
  command = plan
  variables {
    eks_prometheus_remote_write_url = "http://example.com/api/v1/write"
  }
  expect_failures = [var.eks_prometheus_remote_write_url]
}

run "network_observability_reuses_existing_scope" {
  command = plan
  variables {
    eks_enabled                        = true
    eks_admin_principal_arns           = ["arn:aws:iam::123456789012:role/admin"]
    eks_network_observability_enabled  = true
    eks_network_flow_monitor_scope_arn = "arn:aws:networkflowmonitor:us-east-1:123456789012:scope/d894fc8f-92ab-4c38-a32a-04fb931bcbf1"
  }
  assert {
    condition     = length(aws_networkflowmonitor_scope.main) == 0 && aws_networkflowmonitor_monitor.main[0].scope_arn == "arn:aws:networkflowmonitor:us-east-1:123456789012:scope/d894fc8f-92ab-4c38-a32a-04fb931bcbf1"
    error_message = "An existing scope must be reused, not created again."
  }
}

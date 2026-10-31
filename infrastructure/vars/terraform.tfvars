environment        = "demo"
userid             = "JDHARMAPURI"
aws_region         = "us-east-1"
vpc_cidr           = "10.0.0.0/16"
availability_zones = ["us-east-1a", "us-east-1b"]
# False = one NAT per AZ. True reduces demo costs but makes egress depend on one AZ.
single_nat_gateway = false

ses_enabled = true
ses_domain  = "jithendar.com"

ecr_pull_principals = {}

eks_enabled = true
# t4g.medium stops at 17 Pods per node; the add-ons here need more. Changing this replaces the node group.
eks_node_instance_types = ["t4g.large"]
# The role is created by eks-roles.tf. Root is listed for the EKS console while the account has no IAM users.
eks_admin_principal_arns = [
  "arn:aws:iam::881026659929:role/roboshop-demo-eks-admin",
  "arn:aws:iam::881026659929:root",
]
# Without these the API is private-only and unreachable from outside the VPC: home IP, mk4 server.
eks_public_access_cidrs = ["122.177.247.138/32", "46.224.38.14/32"]
# Fargate is x86 only: keep arm64 service images out of these namespaces.
eks_fargate_namespaces = ["fargate"]

eks_network_observability_enabled = true
# Created through the EKS console; AWS allows one scope per account and region.
eks_network_flow_monitor_scope_arn = "arn:aws:networkflowmonitor:us-east-1:881026659929:scope/d894fc8f-92ab-4c38-a32a-04fb931bcbf1"

eks_prometheus_remote_write_url = "https://jithendar.com/prometheus/api/v1/write"

eks_cloudwatch_observability_enabled = true

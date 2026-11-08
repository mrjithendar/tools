locals {
  common_tags = merge(var.tags, {
    Project     = "roboshop-ai"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }, var.userid != "" ? { Owner = var.userid } : {})
  name_prefix    = "roboshop"
  privateSubnets = aws_subnet.vpc_private_subnets[*].id
  publicSubnets  = aws_subnet.vpc_public_subnets[*].id
  subnets        = concat(local.privateSubnets, local.publicSubnets)
  # Subnets, route tables and NAT gateways exist only with the VPC.
  vpc_az_count                         = var.vpc_enabled ? length(var.availability_zones) : 0
  nat_count                            = var.vpc_enabled ? (var.single_nat_gateway ? 1 : length(var.availability_zones)) : 0
  bedrock_enabled                      = length(var.bedrock_trusted_principal_arns) > 0
  bedrock_profile_arn                  = "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.bedrock.account_id}:inference-profile/${var.bedrock_inference_profile_id}"
  eks_name                             = "roboshop-${var.environment}"
  eks_fargate_enabled                  = var.eks_enabled && length(var.eks_fargate_namespaces) > 0
  eks_network_observability_enabled    = var.eks_enabled && var.eks_network_observability_enabled
  eks_cloudwatch_observability_enabled = var.eks_enabled && var.eks_cloudwatch_observability_enabled
  eks_ingress_enabled                  = var.eks_enabled && var.eks_ingress_enabled
  eks_observability_addons = [
    "cert-manager",
    "eks-node-monitoring-agent",
    "fluent-bit",
    "kube-state-metrics",
    "prometheus-node-exporter",
  ]
}

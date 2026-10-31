resource "aws_iam_role" "eks_cluster" {
  count              = var.eks_enabled ? 1 : 0
  name               = "${local.eks_name}-cluster"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "eks.amazonaws.com" } }] })
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_cluster" {
  count      = var.eks_enabled ? 1 : 0
  role       = aws_iam_role.eks_cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks_nodes" {
  count              = var.eks_enabled ? 1 : 0
  name               = "${local.eks_name}-nodes"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Action = "sts:AssumeRole", Principal = { Service = "ec2.amazonaws.com" } }] })
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eks_nodes" {
  for_each   = var.eks_enabled ? toset(["AmazonEKSWorkerNodePolicy", "AmazonEC2ContainerRegistryPullOnly", "AmazonEKS_CNI_Policy"]) : toset([])
  role       = aws_iam_role.eks_nodes[0].name
  policy_arn = "arn:aws:iam::aws:policy/${each.value}"
}

# Cluster administrator role, granted access through eks_admin_principal_arns in the tfvars. The trust policy
# lets IAM users and roles in this account assume it if they also hold sts:AssumeRole; the root user cannot.
resource "aws_iam_role" "eks_admin" {
  count                = var.eks_enabled ? 1 : 0
  name                 = "${local.eks_name}-eks-admin"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.bedrock.account_id}:root" }
    }]
  })
  tags = local.common_tags
}

# Needed by `aws eks update-kubeconfig`; Kubernetes permissions come from the EKS access entry.
resource "aws_iam_role_policy" "eks_admin" {
  count = var.eks_enabled ? 1 : 0
  name  = "describe-cluster"
  role  = aws_iam_role.eks_admin[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "eks:DescribeCluster"
      Resource = aws_eks_cluster.main[0].arn
    }]
  })
}

# Lets the kubelet on Fargate register with the cluster and pull images from ECR.
resource "aws_iam_role" "eks_fargate" {
  count = local.eks_fargate_enabled ? 1 : 0
  name  = "${local.eks_name}-fargate"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "eks-fargate-pods.amazonaws.com" }
      Condition = {
        ArnLike = { "aws:SourceArn" = "arn:aws:eks:${var.aws_region}:${data.aws_caller_identity.bedrock.account_id}:fargateprofile/${local.eks_name}/*" }
      }
    }]
  })
  tags = local.common_tags
}
resource "aws_iam_role_policy_attachment" "eks_fargate" {
  count      = local.eks_fargate_enabled ? 1 : 0
  role       = aws_iam_role.eks_fargate[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

# Lets the Network Flow Monitor agent publish flow data, through EKS Pod Identity.
resource "aws_iam_role" "eks_network_flow_monitor" {
  count = local.eks_network_observability_enabled ? 1 : 0
  name  = "${local.eks_name}-network-flow-monitor"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })
  tags = local.common_tags
}
resource "aws_iam_role_policy_attachment" "eks_network_flow_monitor" {
  count      = local.eks_network_observability_enabled ? 1 : 0
  role       = aws_iam_role.eks_network_flow_monitor[0].name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchNetworkFlowMonitorAgentPublishPolicy"
}

# Lets the CloudWatch agent publish metrics, logs and traces, through EKS Pod Identity.
resource "aws_iam_role" "eks_cloudwatch_observability" {
  count = local.eks_cloudwatch_observability_enabled ? 1 : 0
  name  = "${local.eks_name}-cloudwatch-observability"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })
  tags = local.common_tags
}
resource "aws_iam_role_policy_attachment" "eks_cloudwatch_observability" {
  for_each   = local.eks_cloudwatch_observability_enabled ? toset(["CloudWatchAgentServerPolicy", "AWSXrayWriteOnlyAccess"]) : toset([])
  role       = aws_iam_role.eks_cloudwatch_observability[0].name
  policy_arn = "arn:aws:iam::aws:policy/${each.value}"
}

# Account-wide, one per account: the "Start discovering Services" step for Application Signals.
resource "aws_iam_service_linked_role" "application_signals" {
  count            = local.eks_cloudwatch_observability_enabled ? 1 : 0
  aws_service_name = "application-signals.cloudwatch.amazonaws.com"
}

# Lets the EBS CSI controller create and attach volumes, through EKS Pod Identity.
resource "aws_iam_role" "eks_ebs_csi" {
  count = var.eks_enabled ? 1 : 0
  name  = "${local.eks_name}-ebs-csi"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })
  tags = local.common_tags
}
resource "aws_iam_role_policy_attachment" "eks_ebs_csi" {
  count      = var.eks_enabled ? 1 : 0
  role       = aws_iam_role.eks_ebs_csi[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"
}

# Lets the AWS Load Balancer Controller manage the NLB, through EKS Pod Identity. Policy: policies/, the upstream one.
resource "aws_iam_role" "eks_load_balancer_controller" {
  count = local.eks_ingress_enabled ? 1 : 0
  name  = "${local.eks_name}-load-balancer-controller"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = ["sts:AssumeRole", "sts:TagSession"]
      Principal = { Service = "pods.eks.amazonaws.com" }
    }]
  })
  tags = local.common_tags
}

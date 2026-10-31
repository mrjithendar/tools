# Worker nodes for the cluster in eks_cluster.tf; opt-in through eks_enabled.
variable "eks_node_instance_types" {
  type    = list(string)
  default = ["t4g.medium"]
}
variable "eks_node_count" {
  type    = number
  default = 2
  validation {
    condition     = var.eks_node_count >= 2 && var.eks_node_count <= 6 && floor(var.eks_node_count) == var.eks_node_count
    error_message = "Choose 2 through 6 worker nodes."
  }
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
resource "aws_eks_node_group" "main" {
  count           = var.eks_enabled ? 1 : 0
  cluster_name    = aws_eks_cluster.main[0].name
  node_group_name = "general"
  node_role_arn   = aws_iam_role.eks_nodes[0].arn
  subnet_ids      = local.privateSubnets
  version         = var.eks_version
  ami_type        = "AL2023_ARM_64_STANDARD" # CI publishes linux/arm64 images only
  instance_types  = var.eks_node_instance_types
  capacity_type   = "ON_DEMAND"
  disk_size       = 50
  scaling_config {
    desired_size = var.eks_node_count
    min_size     = 2
    max_size     = 2
  }
  update_config { max_unavailable = 1 }
  tags       = local.common_tags
  depends_on = [aws_iam_role_policy_attachment.eks_nodes, aws_route_table_association.pr_rta, aws_route_table_association.pl_rta]
}

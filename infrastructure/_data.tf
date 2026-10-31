data "aws_availability_zones" "azs" {
  state = "available"
  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

data "aws_region" "current" {}

# Short-lived token for the Helm provider; needs no AWS CLI on the runner.
data "aws_eks_cluster_auth" "main" {
  count = var.eks_enabled ? 1 : 0
  name  = aws_eks_cluster.main[0].name
}

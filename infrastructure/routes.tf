resource "aws_route_table" "pl_rt" {
  count  = var.vpc_enabled ? 1 : 0
  vpc_id = aws_vpc.vpc[0].id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw[0].id
  }
  tags = merge(local.common_tags, { Name = "${local.name_prefix}-public-rt-${var.environment}" })
}

resource "aws_route_table_association" "pl_rta" {
  count          = local.vpc_az_count
  subnet_id      = local.publicSubnets[count.index]
  route_table_id = aws_route_table.pl_rt[0].id
}

resource "aws_route_table" "pr_rt" {
  count  = local.vpc_az_count
  vpc_id = aws_vpc.vpc[0].id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw[var.single_nat_gateway ? 0 : count.index].id
  }
  tags = merge(local.common_tags, { Name = "${local.name_prefix}-private-rt-${count.index + 1}-${var.environment}" })
}

resource "aws_route_table_association" "pr_rta" {
  count          = local.vpc_az_count
  subnet_id      = local.privateSubnets[count.index]
  route_table_id = aws_route_table.pr_rt[count.index].id
}

# ECR image layers use S3. Keep this traffic on AWS's gateway endpoint.
resource "aws_vpc_endpoint" "s3" {
  count             = var.vpc_enabled ? 1 : 0
  vpc_id            = aws_vpc.vpc[0].id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.pr_rt[*].id
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-s3-${var.environment}" })
}

moved {
  from = aws_route_table.pl_rt
  to   = aws_route_table.pl_rt[0]
}

moved {
  from = aws_vpc_endpoint.s3
  to   = aws_vpc_endpoint.s3[0]
}

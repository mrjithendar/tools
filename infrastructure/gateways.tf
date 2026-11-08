resource "aws_internet_gateway" "igw" {
  count  = var.vpc_enabled ? 1 : 0
  vpc_id = aws_vpc.vpc[0].id
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-igw-${var.environment}" })
}

resource "aws_eip" "eip" {
  count  = local.nat_count
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${local.name_prefix}-eip-${count.index + 1}-${var.environment}" })
}

resource "aws_nat_gateway" "ngw" {
  count             = local.nat_count
  connectivity_type = "public"
  allocation_id     = aws_eip.eip[count.index].id
  subnet_id         = local.publicSubnets[count.index]
  tags              = merge(local.common_tags, { Name = "${local.name_prefix}-nat-${count.index + 1}-${var.environment}" })
  depends_on        = [aws_internet_gateway.igw]
}

moved {
  from = aws_internet_gateway.igw
  to   = aws_internet_gateway.igw[0]
}

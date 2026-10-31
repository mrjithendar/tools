output "vpc_cidr" {
  value = aws_vpc.vpc.cidr_block
}

output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "private_subnets" {
  value = local.privateSubnets
}

output "public_subnets" {
  value = local.publicSubnets
}

output "subnets" {
  value = local.subnets
}

output "public_rt" {
  value = aws_route_table.pl_rt.id
}

output "private_rt" {
  value = aws_route_table.pr_rt[*].id
}

output "availability_zones" {
  value = var.availability_zones
}

output "eks_subnet_ids" {
  description = "Private subnets for the EKS control plane ENIs and managed node groups."
  value       = local.privateSubnets
}

output "nat_gateway_ids" {
  value = aws_nat_gateway.ngw[*].id
}

output "ecr_repository_urls" {
  description = "Docker push/pull URLs keyed by repository name."
  value       = { for name, repository in aws_ecr_repository.services : name => repository.repository_url }
}

output "ecr_repository_arns" {
  description = "Repository ARNs for scoping CI publishing and EKS pulling IAM permissions."
  value       = { for name, repository in aws_ecr_repository.services : name => repository.arn }
}

output "shopping_agent_bedrock_role_arn" {
  description = "Role ARN for an AWS SDK assume-role profile; null when disabled."
  value       = try(aws_iam_role.shopping_agent_bedrock[0].arn, null)
}

output "eks_admin_role_arn" {
  value = try(aws_iam_role.eks_admin[0].arn, null)
}

output "eks_cluster_name" {
  value = var.eks_enabled ? aws_eks_cluster.main[0].name : null
}

output "ses_dns_records" {
  description = "Publish these DNS records (DKIM CNAMEs must be DNS-only, not proxied). MAIL FROM MX priority is included in value."
  value = var.ses_enabled ? concat(
    [for token in aws_sesv2_email_identity.store[0].dkim_signing_attributes[0].tokens : {
      type  = "CNAME"
      name  = "${token}._domainkey.${var.ses_domain}"
      value = "${token}.dkim.amazonses.com"
    }],
    [
      { type = "MX", name = "bounce.${var.ses_domain}", value = "10 feedback-smtp.${var.aws_region}.amazonses.com" },
      { type = "TXT", name = "bounce.${var.ses_domain}", value = "v=spf1 include:amazonses.com ~all" }
    ]
  ) : []
}

output "ses_smtp" {
  description = "SMTP connection settings. The IAM user name is not the SMTP login; create region-specific SMTP credentials separately."
  value = var.ses_enabled ? {
    host         = "email-smtp.${var.aws_region}.amazonaws.com"
    port         = 587
    security     = "starttls"
    from         = "no-reply@${var.ses_domain}"
    iam_user     = aws_iam_user.ses_smtp[0].name
    identity_arn = aws_sesv2_email_identity.store[0].arn
  } : null
}

output "eks_load_balancer_controller_role_arn" {
  description = "Pod Identity role of the AWS Load Balancer Controller; null when eks_ingress_enabled is false."
  value       = try(aws_iam_role.eks_load_balancer_controller[0].arn, null)
}

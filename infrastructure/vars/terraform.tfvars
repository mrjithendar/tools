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
# Role created by eks-roles.tf; EKS does not accept the account root.
eks_admin_principal_arns = ["arn:aws:iam::881026659929:role/roboshop-demo-eks-admin"]
# Without these the API is private-only and unreachable from outside the VPC: home IP, mk4 server.
eks_public_access_cidrs = ["122.177.247.138/32", "46.224.38.14/32"]

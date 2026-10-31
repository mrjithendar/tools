variable "environment" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,19}$", var.environment))
    error_message = "Use a lowercase environment name, up to 20 characters."
  }
}

variable "userid" {
  description = "Owner identifier for resource tags (not an AWS credential)."
  type        = string
  default     = ""
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "vpc_cidr" {
  description = "IPv4 /16 network, checked against existing networks before peering."
  type        = string
  default     = "10.0.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.vpc_cidr)) && can(regex("/16$", var.vpc_cidr))
    error_message = "Provide an IPv4 /16 CIDR for this subnet layout."
  }
}

variable "availability_zones" {
  description = "Two or three distinct standard AZs in aws_region, in stable order. Changing order replaces subnets."
  type        = list(string)
  validation {
    condition     = length(var.availability_zones) >= 2 && length(var.availability_zones) <= 3 && length(distinct(var.availability_zones)) == length(var.availability_zones)
    error_message = "Specify two or three distinct availability zones."
  }
}

variable "single_nat_gateway" {
  description = "Cost-saving demo option. True routes all private subnets via the first AZ and loses AZ-level egress redundancy."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Additional organizational tags."
  type        = map(string)
  default     = {}
}

variable "ecr_repository_names" {
  description = "Private ECR repository names. Defaults match the service image names and CI's roboshop prefix. Use [] to manage no repositories."
  type        = list(string)
  nullable    = false
  default = [
    "roboshop-ai-gateway",
    "roboshop-cart-service",
    "roboshop-catalogue-service",
    "roboshop-currency-service",
    # roboshop-frontend and roboshop-nginx: retired into roboshop-web; kept for rollback.
    "roboshop-frontend",
    "roboshop-mcp-server",
    "roboshop-nginx",
    "roboshop-payment-service",
    "roboshop-shipping",
    "roboshop-moks",
    "roboshop-shopping-agent",
    "roboshop-user-service",
    "roboshop-web",
    "roboshop-kafka-bridge",
  ]

  validation {
    condition     = length(distinct(var.ecr_repository_names)) == length(var.ecr_repository_names)
    error_message = "ECR repository names must be unique."
  }

  validation {
    condition = alltrue([
      for name in var.ecr_repository_names :
      length(name) >= 2 && length(name) <= 256 && can(regex("^[a-z][a-z0-9]*([._/-][a-z0-9]+)*$", name))
    ])
    error_message = "Use 2–256 character lowercase repository names starting with a letter; separate alphanumeric segments with a dot, underscore, hyphen or slash."
  }
}

variable "ses_enabled" {
  description = "Provision SES domain verification and a restricted SMTP IAM user. DNS verification is managed separately."
  type        = bool
  default     = false
}

variable "ses_domain" {
  description = "Domain used for transactional emails."
  type        = string
  default     = "jithendar.com"
  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$", var.ses_domain))
    error_message = "Provide a lowercase DNS domain, without a scheme or path."
  }
}

variable "ecr_pull_principals" {
  description = "Repository names mapped to IAM principal ARNs allowed to pull. Prefer role ARNs; account root ARNs delegate access to that account."
  type        = map(list(string))
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for name, principals in var.ecr_pull_principals :
      contains(var.ecr_repository_names, name) && length(principals) > 0 && alltrue([
        for principal in principals : can(regex("^arn:aws:iam::[0-9]{12}:(root|role/.+|user/.+)$", principal))
      ])
    ])
    error_message = "Pull grants must name a managed repository and at least one explicit IAM account, role or user ARN."
  }
}

variable "bedrock_trusted_principal_arns" {
  description = "Existing IAM user/role ARNs allowed to assume the shopping-agent role. Empty disables creation. Never use STS session ARNs."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for arn in var.bedrock_trusted_principal_arns : can(regex("^arn:aws:iam::[0-9]{12}:(user|role)/[A-Za-z0-9+=,.@_/-]+$", arn))])
    error_message = "Provide exact IAM user or role ARNs, not wildcard, root, or STS session principals."
  }
}

variable "bedrock_inference_profile_id" {
  description = "US inference profile allowed for the shopping agent. Change together with model ID."
  type        = string
  default     = "us.amazon.nova-2-lite-v1:0"
  validation {
    condition     = can(regex("^us\\.[a-zA-Z0-9.:-]+$", var.bedrock_inference_profile_id))
    error_message = "Use an exact US inference profile ID."
  }
}

variable "bedrock_model_id" {
  type    = string
  default = "amazon.nova-2-lite-v1:0"
  validation {
    condition     = can(regex("^[a-zA-Z0-9.:-]+$", var.bedrock_model_id))
    error_message = "Use an exact foundation model ID, without wildcards."
  }
}

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

variable "eks_enabled" {
  type    = bool
  default = false
}

variable "eks_version" {
  description = "1.36 is in EKS standard support and within cert-manager 1.21's tested range."
  type        = string
  default     = "1.36"
}

variable "eks_admin_principal_arns" {
  description = "IAM role/user or account root ARNs for cluster administrators; not STS session ARNs."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for arn in var.eks_admin_principal_arns : can(regex("^arn:aws:iam::[0-9]{12}:(root|(role|user)/[A-Za-z0-9+=,.@_/-]+)$", arn))])
    error_message = "Use IAM role/user or account root ARNs, not STS assumed-role session ARNs."
  }
}

variable "eks_public_access_cidrs" {
  description = "Admin/CI public IPv4 CIDRs; empty means private-only API."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for c in var.eks_public_access_cidrs : can(cidrnetmask(c)) && !endswith(c, "/0")])
    error_message = "Use restricted IPv4 CIDRs; world-open API access is not allowed."
  }
}

variable "eks_private_access_cidrs" {
  description = "Connected runner/admin IPv4 CIDRs allowed to the private EKS API on TCP 443. Does not create routing or VPN connectivity."
  type        = set(string)
  default     = []
  validation {
    condition     = alltrue([for c in var.eks_private_access_cidrs : can(cidrnetmask(c)) && !endswith(c, "/0")])
    error_message = "Use restricted IPv4 CIDRs for private API access."
  }
}

variable "eks_fargate_namespaces" {
  description = "Kubernetes namespaces whose Pods run on Fargate. Empty creates no profile. Fargate is x86 only, so these need linux/amd64 images."
  type        = set(string)
  default     = []
  validation {
    condition     = length(var.eks_fargate_namespaces) <= 5 && alltrue([for ns in var.eks_fargate_namespaces : can(regex("^[a-z0-9*?]([-a-z0-9*?]*[a-z0-9*?])?$", ns))])
    error_message = "Use up to five namespace names; * and ? wildcards are allowed."
  }
}

variable "eks_network_observability_enabled" {
  description = "Enable EKS Container Network Observability: Network Flow Monitor scope, monitor and agent add-on. Billed per monitored node."
  type        = bool
  default     = false
}

variable "eks_network_flow_monitor_scope_arn" {
  description = "Existing Network Flow Monitor scope to use. Empty creates one; AWS allows one per account and region."
  type        = string
  default     = ""
  validation {
    condition     = var.eks_network_flow_monitor_scope_arn == "" || can(regex("^arn:aws:networkflowmonitor:[a-z0-9-]+:[0-9]{12}:scope/[0-9a-f-]+$", var.eks_network_flow_monitor_scope_arn))
    error_message = "Provide a Network Flow Monitor scope ARN."
  }
}

variable "eks_cloudwatch_observability_enabled" {
  description = "Install the CloudWatch add-on: Application Signals, Container Insights and OTel Container Insights. Billed by CloudWatch usage."
  type        = bool
  default     = false
}

variable "eks_prometheus_remote_write_url" {
  description = "Prometheus remote write endpoint for cluster metrics. Empty installs no agent."
  type        = string
  default     = ""
  validation {
    condition     = var.eks_prometheus_remote_write_url == "" || startswith(var.eks_prometheus_remote_write_url, "https://")
    error_message = "Use an https:// URL: the write password is sent with every request."
  }
}

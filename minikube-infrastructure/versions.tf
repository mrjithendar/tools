# Cluster add-ons on the mk4 Minikube cluster, installed as Helm releases by Terraform.
# Applied by .github/workflows/minikube-terraform-apply.yml on master, or by a person from a machine
# whose kubeconfig reaches mk4 (README.md). Separate from infrastructure/ (AWS): own state, own workflows.
terraform {
  required_version = ">= 1.10, < 2.0"
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }
  }

  backend "s3" {
    bucket       = "jithendardharmapuri"
    key          = "terraform/minikube-mk4.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "helm" {
  kubernetes = {
    config_path    = pathexpand(var.kubeconfig_path)
    config_context = var.kube_context
  }
}

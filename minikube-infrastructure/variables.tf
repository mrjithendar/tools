variable "kubeconfig_path" {
  description = "Kubeconfig that contains the mk4 context."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Kubeconfig context of the Minikube cluster."
  type        = string
  default     = "mk4"
}

variable "helm_timeout" {
  description = "Seconds Helm waits for each release to become ready."
  type        = number
  default     = 600
}

variable "kong_enabled" {
  description = "Install the Kong release. Leave false until the cutover window."
  type        = bool
  default     = false
}

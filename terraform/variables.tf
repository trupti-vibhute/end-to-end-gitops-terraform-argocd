variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "gitops-eks-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS control plane"
  type        = string
  default     = "1.35"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "argocd_version" {
  description = "ArgoCD release to install (pinned so every apply installs the same version)"
  type        = string
  default     = "v3.5.6"
}

variable "api_allowed_cidrs" {
  description = "CIDRs allowed to reach the EKS API server's public endpoint (e.g. your IP as x.x.x.x/32). Set in terraform.tfvars."
  type        = list(string)

  validation {
    condition     = length(var.api_allowed_cidrs) > 0 && !contains(var.api_allowed_cidrs, "0.0.0.0/0")
    error_message = "Give at least one CIDR, and never 0.0.0.0/0: that exposes the API server to the whole internet."
  }
}

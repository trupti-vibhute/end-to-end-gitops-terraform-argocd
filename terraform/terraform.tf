terraform {
  required_version = ">= 1.5"

  required_providers {
    # Creates AWS resources: VPC, subnets, NAT, EKS, IAM roles, EBS add-on
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Talks to the Kubernetes API inside EKS (e.g. creates the argocd namespace)
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.20"
    }
    # Applies raw YAML manifests (ArgoCD install + our ArgoCD Application)
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    # Downloads the official ArgoCD install.yaml from GitHub
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

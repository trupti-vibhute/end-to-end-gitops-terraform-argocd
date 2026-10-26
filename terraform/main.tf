################################################################################
# Part 1: Networking (VPC)
################################################################################

# Look up the AZs in this region that are enabled by default
data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  # Use 2 AZs: enough for high availability, fewer NAT/subnet costs than 3
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  # Carve /24 subnets out of the VPC CIDR, one per AZ:
  # private -> 10.0.0.0/24, 10.0.1.0/24   (worker nodes, pods)
  # public  -> 10.0.100.0/24, 10.0.101.0/24 (load balancers, NAT gateway)
  private_subnets = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, i)]
  public_subnets  = [for i, az in local.azs : cidrsubnet(var.vpc_cidr, 8, i + 100)]

  # Private nodes reach the internet (image pulls, AWS APIs) through NAT.
  # A single NAT gateway keeps cost down; use one per AZ in production.
  enable_nat_gateway = true
  single_nat_gateway = true

  # Required by EKS so nodes and endpoints resolve by DNS name
  enable_dns_hostnames = true
  enable_dns_support   = true

  # Tell Kubernetes where to place load balancers:
  # internet-facing LBs (frontend, ArgoCD UI) go in public subnets
  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  # internal LBs go in private subnets
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

################################################################################
# Part 2: EKS cluster (control plane + worker nodes)
################################################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version

  # Lets kubectl/Terraform on your laptop reach the Kubernetes API.
  # Nodes still talk to it privately from inside the VPC.
  cluster_endpoint_public_access = true

  vpc_id = module.vpc.vpc_id
  # Worker nodes and the control plane's network interfaces live in private subnets
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # Creates the OIDC provider so pods can assume IAM roles (IRSA).
  # The EBS CSI driver in Part 3 depends on this.
  enable_irsa = true

  # Grants the IAM identity running Terraform admin access to the cluster.
  # Without this, Terraform could create the cluster but not deploy into it.
  enable_cluster_creator_admin_permissions = true

  eks_managed_node_groups = {
    default = {
      # Amazon Linux 2 images aren't published for Kubernetes 1.33+, so use AL2023
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.medium"]

      min_size     = 2
      max_size     = 3
      desired_size = 2
      subnet_ids   = module.vpc.private_subnets
    }
  }

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

################################################################################
# Part 3: Storage (EBS CSI driver) so Postgres gets a persistent disk
################################################################################

# IAM role that only the EBS CSI controller's service account can assume (IRSA)
module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name_prefix      = "ebs-csi-driver-"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

# The driver itself, installed as an EKS-managed add-on
resource "aws_eks_addon" "ebs_csi_driver" {
  cluster_name             = module.eks.cluster_name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn

  # The add-on's pods need worker nodes to run on
  depends_on = [module.eks]

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

# Default StorageClass backed by the CSI driver. EKS no longer marks gp2 as
# default (since 1.30), and gp3 is cheaper and faster than gp2.
resource "kubernetes_storage_class_v1" "gp3" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }

  depends_on = [aws_eks_addon.ebs_csi_driver]
}

################################################################################
# Part 4: ArgoCD (GitOps controller) + our Application
################################################################################

resource "kubernetes_namespace_v1" "argocd" {
  metadata {
    name = "argocd"
  }

  depends_on = [module.eks]
}

# Download the official install manifest for the pinned ArgoCD version
data "http" "argocd_manifest" {
  url = "https://raw.githubusercontent.com/argoproj/argo-cd/${var.argocd_version}/manifests/install.yaml"
}

# Split the multi-document YAML into individual Kubernetes objects
data "kubectl_file_documents" "argocd" {
  content = data.http.argocd_manifest.response_body
}

resource "kubectl_manifest" "argocd" {
  for_each = data.kubectl_file_documents.argocd.manifests

  yaml_body          = each.value
  override_namespace = kubernetes_namespace_v1.argocd.metadata[0].name

  # ArgoCD's CRDs are too large for client-side apply (annotation size limit)
  server_side_apply = true
  # On destroy, wait until each object is really gone before moving on
  wait = true
}

# The ArgoCD Application: tells ArgoCD to sync ../manifests from our Git repo
resource "kubectl_manifest" "app_deployment" {
  yaml_body = file("${path.module}/../manifests/argocd-app.yaml")

  # On destroy, wait for ArgoCD to delete the app (and its load balancer / EBS volume)
  wait = true

  # The storage class dependency keeps the CSI driver alive until the app's volume is deleted
  depends_on = [kubectl_manifest.argocd, kubernetes_storage_class_v1.gp3]
}

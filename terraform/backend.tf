# State lives in S3 (created by ../bootstrap) instead of on one laptop:
# shared, versioned, encrypted, and locked so two applies can't collide.
terraform {
  backend "s3" {
    bucket = "gitops-eks-tfstate-20261026162316708500000001"
    key    = "eks-gitops/terraform.tfstate"
    region = "ap-south-1"

    encrypt = true
    # Native S3 locking (Terraform >= 1.10), no DynamoDB table needed
    use_lockfile = true
  }
}

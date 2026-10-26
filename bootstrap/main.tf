# One-time setup: the S3 bucket that holds the main stack's Terraform state.
# Its own (tiny) state stays local, since the bucket can't store the state
# of the thing that creates it. Apply this once, before terraform/.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "ap-south-1"
}

resource "aws_s3_bucket" "tfstate" {
  # AWS appends a random suffix, so the name is globally unique
  bucket_prefix = "gitops-eks-tfstate-"

  # Losing this bucket means losing track of every resource in the cluster
  lifecycle {
    prevent_destroy = true
  }
}

# Every state write is kept, so a bad apply can be rolled back
resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

# State holds secrets in plain text (e.g. the ArgoCD install), so encrypt at rest
resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Reject any request that isn't over HTTPS
resource "aws_s3_bucket_policy" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.tfstate.arn, "${aws_s3_bucket.tfstate.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.tfstate]
}

output "state_bucket" {
  description = "Put this name in terraform/backend.tf"
  value       = aws_s3_bucket.tfstate.bucket
}

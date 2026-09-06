# terraform/bootstrap
#
# This is a small, separate Terraform project whose only job is to create
# the S3 bucket that terraform/infrastructure will later use as its remote
# state backend. It has to be applied FIRST, and it keeps its own local
# state (not stored in S3), because the bucket doesn't exist yet.
#
# Usage:
#   cd terraform/bootstrap
#   terraform init
#   terraform apply
#   # note the bucket name from the output, put it into
#   # terraform/infrastructure/backend.tf

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "tf_state" {
  bucket = "terraform-state-ekart-cicd-${random_id.suffix.hex}"

  # Safety net: prevents `terraform destroy` from silently wiping the
  # state bucket for the main infrastructure project.
  lifecycle {
    prevent_destroy = false
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table for Terraform state locking (recommended alongside an S3
# backend so two `terraform apply` runs can't race each other).
resource "aws_dynamodb_table" "tf_lock" {
  name         = "terraform-lock-ekart-cicd"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

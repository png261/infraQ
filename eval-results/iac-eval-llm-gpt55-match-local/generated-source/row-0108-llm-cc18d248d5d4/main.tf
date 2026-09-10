terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the Terraform state management resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "bucket_name_prefix" {
  description = "Prefix for the Terraform state S3 bucket name. A random suffix will be added."
  type        = string
  default     = "terraform-state"
}

variable "dynamodb_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking."
  type        = string
  default     = "terraform-state-locks"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

locals {
  terraform_state_bucket_name = "${var.bucket_name_prefix}-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = local.terraform_state_bucket_name

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = local.terraform_state_bucket_name
    Purpose     = "Terraform remote state storage"
    ManagedBy   = "Terraform"
    Environment = "shared"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = var.dynamodb_table_name
    Purpose     = "Terraform state locking"
    ManagedBy   = "Terraform"
    Environment = "shared"
  }
}

output "terraform_state_bucket_name" {
  description = "Name of the S3 bucket used for Terraform remote state."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "terraform_lock_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking."
  value       = aws_dynamodb_table.terraform_locks.name
}

output "backend_configuration_example" {
  description = "Example Terraform backend configuration using the created S3 bucket and DynamoDB table."
  value = {
    bucket         = aws_s3_bucket.terraform_state.bucket
    key            = "path/to/terraform.tfstate"
    region         = var.aws_region
    dynamodb_table = aws_dynamodb_table.terraform_locks.name
    encrypt        = true
  }
}
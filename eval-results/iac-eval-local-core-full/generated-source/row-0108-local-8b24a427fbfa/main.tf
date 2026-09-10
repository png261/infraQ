terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state storage."
  type        = string
  default     = "terraform-state-management-us-east-1"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.state_bucket_name))
    error_message = "The state_bucket_name value must be a valid S3 bucket name between 3 and 63 characters using lowercase letters, numbers, dots, and hyphens."
  }
}

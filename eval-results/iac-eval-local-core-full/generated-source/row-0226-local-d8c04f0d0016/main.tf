terraform {
  required_version = ">= 1.5.0"

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

resource "aws_iam_role" "dax" {
  name = "iac-eval-dax-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "dax.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_dax_cluster" "example" {
  cluster_name       = "iac-eval-dax-cluster"
  iam_role_arn       = aws_iam_role.dax.arn
  node_type          = "dax.t3.small"
  replication_factor = 1
}

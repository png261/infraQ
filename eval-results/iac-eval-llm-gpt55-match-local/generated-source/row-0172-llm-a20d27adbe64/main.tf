terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the SageMaker Domain will be created."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Name of the SageMaker Domain."
  type        = string
  default     = "example-sagemaker-domain"
}

variable "vpc_cidr" {
  description = "CIDR block for the SageMaker VPC."
  type        = string
  default     = "10.0.0.0/16"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "sagemaker_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "sagemaker-domain-vpc"
  }
}

resource "aws_subnet" "sagemaker_subnet_a" {
  vpc_id            = aws_vpc.sagemaker_vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "sagemaker-domain-subnet-a"
  }
}

resource "aws_subnet" "sagemaker_subnet_b" {
  vpc_id            = aws_vpc.sagemaker_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "sagemaker-domain-subnet-b"
  }
}

resource "aws_iam_role" "sagemaker_execution_role" {
  name = "sagemaker-domain-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "sagemaker-domain-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_sagemaker_domain" "this" {
  domain_name = var.domain_name
  auth_mode   = "IAM"
  vpc_id      = aws_vpc.sagemaker_vpc.id
  subnet_ids = [
    aws_subnet.sagemaker_subnet_a.id,
    aws_subnet.sagemaker_subnet_b.id
  ]

  app_network_access_type = "PublicInternetOnly"

  default_user_settings {
    execution_role = aws_iam_role.sagemaker_execution_role.arn
  }

  retention_policy {
    home_efs_file_system = "Retain"
  }

  tags = {
    Name = var.domain_name
  }

  depends_on = [
    aws_iam_role_policy_attachment.sagemaker_full_access
  ]
}

output "sagemaker_domain_id" {
  description = "ID of the SageMaker Domain."
  value       = aws_sagemaker_domain.this.id
}

output "sagemaker_domain_arn" {
  description = "ARN of the SageMaker Domain."
  value       = aws_sagemaker_domain.this.arn
}

output "sagemaker_execution_role_arn" {
  description = "ARN of the SageMaker execution role."
  value       = aws_iam_role.sagemaker_execution_role.arn
}
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
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "sagemaker_domain_name" {
  description = "Name of the SageMaker Domain."
  type        = string
  default     = "example-sagemaker-domain"
}

variable "sagemaker_user_profile_name" {
  description = "Name of the SageMaker User Profile."
  type        = string
  default     = "example-user-profile"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "sagemaker_vpc" {
  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "sagemaker-vpc"
  }
}

resource "aws_internet_gateway" "sagemaker_igw" {
  vpc_id = aws_vpc.sagemaker_vpc.id

  tags = {
    Name = "sagemaker-igw"
  }
}

resource "aws_subnet" "sagemaker_subnet_a" {
  vpc_id                  = aws_vpc.sagemaker_vpc.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "sagemaker-subnet-a"
  }
}

resource "aws_subnet" "sagemaker_subnet_b" {
  vpc_id                  = aws_vpc.sagemaker_vpc.id
  cidr_block              = "10.10.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "sagemaker-subnet-b"
  }
}

resource "aws_route_table" "sagemaker_public_rt" {
  vpc_id = aws_vpc.sagemaker_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sagemaker_igw.id
  }

  tags = {
    Name = "sagemaker-public-route-table"
  }
}

resource "aws_route_table_association" "sagemaker_subnet_a_assoc" {
  subnet_id      = aws_subnet.sagemaker_subnet_a.id
  route_table_id = aws_route_table.sagemaker_public_rt.id
}

resource "aws_route_table_association" "sagemaker_subnet_b_assoc" {
  subnet_id      = aws_subnet.sagemaker_subnet_b.id
  route_table_id = aws_route_table.sagemaker_public_rt.id
}

resource "aws_iam_role" "sagemaker_execution_role" {
  name = "sagemaker-studio-execution-role"

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
    Name = "sagemaker-studio-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_sagemaker_domain" "sagemaker_domain" {
  domain_name = var.sagemaker_domain_name
  auth_mode   = "IAM"
  vpc_id      = aws_vpc.sagemaker_vpc.id

  subnet_ids = [
    aws_subnet.sagemaker_subnet_a.id,
    aws_subnet.sagemaker_subnet_b.id
  ]

  default_user_settings {
    execution_role = aws_iam_role.sagemaker_execution_role.arn
  }

  tags = {
    Name = var.sagemaker_domain_name
  }

  depends_on = [
    aws_iam_role_policy_attachment.sagemaker_full_access
  ]
}

resource "aws_sagemaker_user_profile" "user_profile" {
  domain_id         = aws_sagemaker_domain.sagemaker_domain.id
  user_profile_name = var.sagemaker_user_profile_name

  user_settings {
    execution_role = aws_iam_role.sagemaker_execution_role.arn
  }

  tags = {
    Name = var.sagemaker_user_profile_name
  }

  depends_on = [
    aws_sagemaker_domain.sagemaker_domain
  ]
}

output "sagemaker_domain_id" {
  description = "The ID of the SageMaker Domain."
  value       = aws_sagemaker_domain.sagemaker_domain.id
}

output "sagemaker_user_profile_name" {
  description = "The SageMaker User Profile name."
  value       = aws_sagemaker_user_profile.user_profile.user_profile_name
}

output "sagemaker_execution_role_arn" {
  description = "The ARN of the SageMaker execution role."
  value       = aws_iam_role.sagemaker_execution_role.arn
}
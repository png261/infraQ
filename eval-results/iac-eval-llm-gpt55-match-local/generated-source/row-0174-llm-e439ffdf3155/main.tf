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

variable "project_name" {
  description = "Name prefix for all created resources."
  type        = string
  default     = "sagemaker-space-demo"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.40.1.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-subnet"
  }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-route-table"
  }
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.main.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

resource "aws_security_group" "sagemaker" {
  name        = "${var.project_name}-sg"
  description = "Security group for SageMaker Domain and Space"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow internal VPC traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

resource "aws_iam_role" "sagemaker_execution_role" {
  name = "${var.project_name}-execution-role"

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
    Name = "${var.project_name}-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_sagemaker_domain" "main" {
  domain_name = "${var.project_name}-domain"
  auth_mode   = "IAM"
  vpc_id      = aws_vpc.main.id
  subnet_ids  = [aws_subnet.main.id]

  app_network_access_type = "PublicInternetOnly"

  default_user_settings {
    execution_role  = aws_iam_role.sagemaker_execution_role.arn
    security_groups = [aws_security_group.sagemaker.id]
  }

  tags = {
    Name = "${var.project_name}-domain"
  }

  depends_on = [
    aws_iam_role_policy_attachment.sagemaker_full_access
  ]
}

resource "aws_sagemaker_space" "main" {
  domain_id  = aws_sagemaker_domain.main.id
  space_name = "${var.project_name}-space"

  space_settings {
    app_type = "JupyterLab"
  }

  tags = {
    Name = "${var.project_name}-space"
  }
}

output "sagemaker_domain_id" {
  description = "ID of the SageMaker Domain."
  value       = aws_sagemaker_domain.main.id
}

output "sagemaker_space_name" {
  description = "Name of the SageMaker Space."
  value       = aws_sagemaker_space.main.space_name
}

output "sagemaker_execution_role_arn" {
  description = "ARN of the SageMaker execution role."
  value       = aws_iam_role.sagemaker_execution_role.arn
}
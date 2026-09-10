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
  description = "AWS region where SageMaker resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "sagemaker-jupyterserver-demo"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "sagemaker_vpc" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "sagemaker_igw" {
  vpc_id = aws_vpc.sagemaker_vpc.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.sagemaker_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sagemaker_igw.id
  }

  tags = {
    Name = "${var.project_name}-public-rt"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.sagemaker_vpc.id
  cidr_block              = "10.40.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.sagemaker_vpc.id
  cidr_block              = "10.40.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-b"
  }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
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

resource "aws_sagemaker_domain" "studio_domain" {
  domain_name = "${var.project_name}-domain"
  auth_mode   = "IAM"
  vpc_id      = aws_vpc.sagemaker_vpc.id
  subnet_ids = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  app_network_access_type = "PublicInternetOnly"

  default_user_settings {
    execution_role = aws_iam_role.sagemaker_execution_role.arn
  }

  tags = {
    Name = "${var.project_name}-domain"
  }

  depends_on = [
    aws_iam_role_policy_attachment.sagemaker_full_access
  ]
}

resource "aws_sagemaker_user_profile" "jupyter_user" {
  domain_id         = aws_sagemaker_domain.studio_domain.id
  user_profile_name = "jupyter-user"

  user_settings {
    execution_role = aws_iam_role.sagemaker_execution_role.arn
  }

  tags = {
    Name = "${var.project_name}-jupyter-user"
  }
}

resource "aws_sagemaker_app" "jupyter_server" {
  domain_id         = aws_sagemaker_domain.studio_domain.id
  user_profile_name = aws_sagemaker_user_profile.jupyter_user.user_profile_name
  app_name          = "default"
  app_type          = "JupyterServer"

  tags = {
    Name = "${var.project_name}-jupyterserver-app"
  }

  depends_on = [
    aws_sagemaker_user_profile.jupyter_user
  ]
}

output "sagemaker_domain_id" {
  description = "The ID of the SageMaker Studio Domain."
  value       = aws_sagemaker_domain.studio_domain.id
}

output "sagemaker_user_profile_name" {
  description = "The SageMaker User Profile name."
  value       = aws_sagemaker_user_profile.jupyter_user.user_profile_name
}

output "sagemaker_jupyter_server_app_arn" {
  description = "The ARN of the SageMaker JupyterServer app."
  value       = aws_sagemaker_app.jupyter_server.arn
}
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
  description = "AWS region where the MSK Serverless cluster will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the MSK Serverless cluster."
  type        = string
  default     = "serverless-msk-cluster"
}

variable "vpc_cidr" {
  description = "CIDR block for the MSK VPC."
  type        = string
  default     = "10.50.0.0/16"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

resource "aws_vpc" "msk" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

resource "aws_subnet" "private" {
  count = 3

  vpc_id                  = aws_vpc.msk.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.cluster_name}-private-subnet-${count.index + 1}"
  }
}

resource "aws_security_group" "msk" {
  name        = "${var.cluster_name}-sg"
  description = "Security group for MSK Serverless cluster"
  vpc_id      = aws_vpc.msk.id

  ingress {
    description = "Allow MSK IAM-authenticated Kafka traffic from within the VPC"
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-sg"
  }
}

resource "aws_msk_serverless_cluster" "this" {
  cluster_name = var.cluster_name

  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }

  vpc_config {
    subnet_ids         = aws_subnet.private[*].id
    security_group_ids = [aws_security_group.msk.id]
  }

  tags = {
    Name        = var.cluster_name
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_iam_role" "msk_client_role" {
  name = "${var.cluster_name}-client-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name      = "${var.cluster_name}-client-role"
    ManagedBy = "terraform"
  }
}

resource "aws_iam_policy" "msk_client_policy" {
  name        = "${var.cluster_name}-client-policy"
  description = "IAM policy allowing clients to connect to and use the MSK Serverless cluster"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeCluster",
          "kafka-cluster:AlterCluster",
          "kafka-cluster:DescribeClusterDynamicConfiguration"
        ]
        Resource = aws_msk_serverless_cluster.this.arn
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:*Topic*",
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData"
        ]
        Resource = "arn:aws:kafka:${var.aws_region}:${data.aws_caller_identity.current.account_id}:topic/${var.cluster_name}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeGroup"
        ]
        Resource = "arn:aws:kafka:${var.aws_region}:${data.aws_caller_identity.current.account_id}:group/${var.cluster_name}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "msk_client_policy_attachment" {
  role       = aws_iam_role.msk_client_role.name
  policy_arn = aws_iam_policy.msk_client_policy.arn
}

output "msk_serverless_cluster_name" {
  description = "Name of the MSK Serverless cluster."
  value       = aws_msk_serverless_cluster.this.cluster_name
}

output "msk_serverless_cluster_arn" {
  description = "ARN of the MSK Serverless cluster."
  value       = aws_msk_serverless_cluster.this.arn
}

output "vpc_id" {
  description = "VPC ID used by the MSK Serverless cluster."
  value       = aws_vpc.msk.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by the MSK Serverless cluster."
  value       = aws_subnet.private[*].id
}

output "security_group_id" {
  description = "Security group ID attached to the MSK Serverless cluster."
  value       = aws_security_group.msk.id
}

output "msk_client_role_arn" {
  description = "IAM role ARN for clients using IAM authentication with MSK Serverless."
  value       = aws_iam_role.msk_client_role.arn
}
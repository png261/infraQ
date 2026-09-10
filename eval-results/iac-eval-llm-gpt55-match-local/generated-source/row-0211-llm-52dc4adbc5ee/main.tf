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
  region = "us-east-2"
}

variable "cluster_name" {
  description = "Name of the MSK Serverless cluster."
  type        = string
  default     = "serverless-msk-cluster"
}

variable "vpc_cidr" {
  description = "CIDR block for the MSK VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets used by MSK Serverless."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
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
  count = 2

  vpc_id                  = aws_vpc.msk.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.cluster_name}-private-${count.index + 1}"
  }
}

resource "aws_security_group" "msk" {
  name        = "${var.cluster_name}-sg"
  description = "Security group for MSK Serverless cluster"
  vpc_id      = aws_vpc.msk.id

  ingress {
    description = "Allow IAM-authenticated Kafka client traffic from within the VPC"
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
    Name = var.cluster_name
  }
}

resource "aws_iam_role" "msk_client" {
  name = "${var.cluster_name}-client-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.cluster_name}-client-role"
  }
}

resource "aws_iam_policy" "msk_client" {
  name        = "${var.cluster_name}-client-policy"
  description = "IAM policy allowing clients to connect to and use the MSK Serverless cluster"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MSKClusterAccess"
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeCluster",
          "kafka-cluster:AlterCluster"
        ]
        Resource = aws_msk_serverless_cluster.this.arn
      },
      {
        Sid    = "MSKTopicAccess"
        Effect = "Allow"
        Action = [
          "kafka-cluster:CreateTopic",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:AlterTopic",
          "kafka-cluster:DeleteTopic",
          "kafka-cluster:ReadData",
          "kafka-cluster:WriteData"
        ]
        Resource = "${replace(aws_msk_serverless_cluster.this.arn, ":cluster/", ":topic/")}/*"
      },
      {
        Sid    = "MSKConsumerGroupAccess"
        Effect = "Allow"
        Action = [
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeGroup"
        ]
        Resource = "${replace(aws_msk_serverless_cluster.this.arn, ":cluster/", ":group/")}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "msk_client" {
  role       = aws_iam_role.msk_client.name
  policy_arn = aws_iam_policy.msk_client.arn
}

resource "aws_iam_instance_profile" "msk_client" {
  name = "${var.cluster_name}-client-instance-profile"
  role = aws_iam_role.msk_client.name
}

output "msk_cluster_name" {
  description = "Name of the MSK Serverless cluster."
  value       = aws_msk_serverless_cluster.this.cluster_name
}

output "msk_cluster_arn" {
  description = "ARN of the MSK Serverless cluster."
  value       = aws_msk_serverless_cluster.this.arn
}

output "msk_vpc_id" {
  description = "VPC ID used by the MSK Serverless cluster."
  value       = aws_vpc.msk.id
}

output "msk_private_subnet_ids" {
  description = "Private subnet IDs used by the MSK Serverless cluster."
  value       = aws_subnet.private[*].id
}

output "msk_security_group_id" {
  description = "Security group ID associated with the MSK Serverless cluster."
  value       = aws_security_group.msk.id
}

output "msk_client_iam_role_arn" {
  description = "IAM role ARN for clients that need to connect to the MSK Serverless cluster."
  value       = aws_iam_role.msk_client.arn
}
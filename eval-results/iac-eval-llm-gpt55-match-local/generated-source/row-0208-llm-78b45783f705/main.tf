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
  description = "AWS region for the MSK Serverless cluster. AWS uses us-east-1 rather than us-east1."
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
  default     = "10.20.0.0/16"
}

variable "subnet_1_cidr" {
  description = "CIDR block for the first MSK subnet."
  type        = string
  default     = "10.20.1.0/24"
}

variable "subnet_2_cidr" {
  description = "CIDR block for the second MSK subnet."
  type        = string
  default     = "10.20.2.0/24"
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "msk" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

resource "aws_subnet" "msk_az1" {
  vpc_id                  = aws_vpc.msk.id
  cidr_block              = var.subnet_1_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.cluster_name}-subnet-az1"
  }
}

resource "aws_subnet" "msk_az2" {
  vpc_id                  = aws_vpc.msk.id
  cidr_block              = var.subnet_2_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.cluster_name}-subnet-az2"
  }
}

resource "aws_security_group" "msk" {
  name        = "${var.cluster_name}-sg"
  description = "Security group for MSK Serverless Kafka access"
  vpc_id      = aws_vpc.msk.id

  ingress {
    description = "Allow IAM-authenticated Kafka client traffic from within the VPC"
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
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
    subnet_ids = [
      aws_subnet.msk_az1.id,
      aws_subnet.msk_az2.id
    ]

    security_group_ids = [
      aws_security_group.msk.id
    ]
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
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
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
  description = "IAM permissions for clients to access MSK Serverless using IAM authentication"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MSKClusterAccess"
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
        Sid    = "MSKTopicAccess"
        Effect = "Allow"
        Action = [
          "kafka-cluster:CreateTopic",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:AlterTopic",
          "kafka-cluster:DeleteTopic",
          "kafka-cluster:ReadData",
          "kafka-cluster:WriteData",
          "kafka-cluster:DescribeTopicDynamicConfiguration",
          "kafka-cluster:AlterTopicDynamicConfiguration"
        ]
        Resource = "*"
      },
      {
        Sid    = "MSKGroupAccess"
        Effect = "Allow"
        Action = [
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeGroup"
        ]
        Resource = "*"
      },
      {
        Sid    = "MSKTransactionalIdAccess"
        Effect = "Allow"
        Action = [
          "kafka-cluster:DescribeTransactionalId",
          "kafka-cluster:AlterTransactionalId"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "msk_client" {
  role       = aws_iam_role.msk_client.name
  policy_arn = aws_iam_policy.msk_client.arn
}

output "msk_serverless_cluster_arn" {
  description = "ARN of the MSK Serverless cluster."
  value       = aws_msk_serverless_cluster.this.arn
}

output "msk_serverless_cluster_name" {
  description = "Name of the MSK Serverless cluster."
  value       = aws_msk_serverless_cluster.this.cluster_name
}

output "msk_client_role_arn" {
  description = "IAM role ARN that Kafka clients can assume."
  value       = aws_iam_role.msk_client.arn
}

output "vpc_id" {
  description = "ID of the VPC containing the MSK Serverless cluster."
  value       = aws_vpc.msk.id
}

output "subnet_ids" {
  description = "Subnet IDs used by the MSK Serverless cluster."
  value = [
    aws_subnet.msk_az1.id,
    aws_subnet.msk_az2.id
  ]
}

output "security_group_id" {
  description = "Security group ID attached to the MSK Serverless cluster."
  value       = aws_security_group.msk.id
}
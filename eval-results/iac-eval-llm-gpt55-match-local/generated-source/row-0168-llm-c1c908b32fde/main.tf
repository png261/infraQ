terraform {
  required_version = ">= 1.3.0"

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
  description = "AWS region where the DAX cluster will be created."
  type        = string
  default     = "us-east-1"
}

variable "dax_cluster_name" {
  description = "Name of the DAX cluster."
  type        = string
  default     = "example-dax-cluster"
}

variable "dax_node_type" {
  description = "DAX node type."
  type        = string
  default     = "dax.r4.large"
}

variable "dax_replication_factor" {
  description = "Number of nodes in the DAX cluster."
  type        = number
  default     = 1
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "dax" {
  name        = "${var.dax_cluster_name}-sg"
  description = "Security group for DAX cluster"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow DAX traffic from within the default VPC"
    from_port   = 8111
    to_port     = 8111
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.dax_cluster_name}-sg"
  }
}

resource "aws_iam_role" "dax_service_role" {
  name = "${var.dax_cluster_name}-service-role"

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

  tags = {
    Name = "${var.dax_cluster_name}-service-role"
  }
}

resource "aws_iam_role_policy_attachment" "dax_dynamodb_access" {
  role       = aws_iam_role.dax_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_dax_subnet_group" "dax" {
  name        = "${var.dax_cluster_name}-subnet-group"
  description = "Subnet group for DAX cluster"
  subnet_ids  = data.aws_subnets.default.ids
}

resource "aws_dax_cluster" "dax" {
  cluster_name       = var.dax_cluster_name
  iam_role_arn       = aws_iam_role.dax_service_role.arn
  node_type          = var.dax_node_type
  replication_factor = var.dax_replication_factor

  subnet_group_name  = aws_dax_subnet_group.dax.name
  security_group_ids = [aws_security_group.dax.id]

  tags = {
    Name = var.dax_cluster_name
  }

  depends_on = [
    aws_iam_role_policy_attachment.dax_dynamodb_access
  ]
}

output "dax_cluster_name" {
  description = "Name of the created DAX cluster."
  value       = aws_dax_cluster.dax.cluster_name
}

output "dax_cluster_arn" {
  description = "ARN of the created DAX cluster."
  value       = aws_dax_cluster.dax.arn
}

output "dax_cluster_discovery_endpoint" {
  description = "DAX cluster discovery endpoint."
  value       = aws_dax_cluster.dax.cluster_address
}
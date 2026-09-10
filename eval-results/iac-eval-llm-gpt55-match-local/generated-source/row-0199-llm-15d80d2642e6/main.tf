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

variable "cluster_name" {
  description = "Name of the DAX cluster."
  type        = string
  default     = "example-dax-cluster"
}

variable "node_type" {
  description = "DAX node type."
  type        = string
  default     = "dax.r4.large"
}

variable "replication_factor" {
  description = "Number of nodes in the DAX cluster."
  type        = number
  default     = 1
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "dax_vpc" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "dax-vpc"
  }
}

resource "aws_subnet" "dax_subnet" {
  vpc_id                  = aws_vpc.dax_vpc.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "dax-subnet"
  }
}

resource "aws_security_group" "dax_sg" {
  name        = "dax-security-group"
  description = "Security group for DAX cluster"
  vpc_id      = aws_vpc.dax_vpc.id

  ingress {
    description = "Allow DAX traffic within the VPC"
    from_port   = 8111
    to_port     = 8111
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.dax_vpc.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "dax-security-group"
  }
}

resource "aws_iam_role" "dax_service_role" {
  name = "dax-service-role"

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
    Name = "dax-service-role"
  }
}

resource "aws_iam_role_policy_attachment" "dax_dynamodb_access" {
  role       = aws_iam_role.dax_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_dax_subnet_group" "dax_subnet_group" {
  name        = "dax-subnet-group"
  description = "Subnet group for DAX cluster"
  subnet_ids  = [aws_subnet.dax_subnet.id]
}

resource "aws_dax_parameter_group" "dax_parameter_group" {
  name        = "dax-parameter-group"
  description = "Parameter group for DAX cluster"
}

resource "aws_dax_cluster" "dax_cluster" {
  cluster_name       = var.cluster_name
  iam_role_arn       = aws_iam_role.dax_service_role.arn
  node_type          = var.node_type
  replication_factor = var.replication_factor

  subnet_group_name    = aws_dax_subnet_group.dax_subnet_group.name
  parameter_group_name = aws_dax_parameter_group.dax_parameter_group.name
  security_group_ids   = [aws_security_group.dax_sg.id]

  depends_on = [
    aws_iam_role_policy_attachment.dax_dynamodb_access
  ]

  tags = {
    Name = var.cluster_name
  }
}

output "dax_cluster_name" {
  description = "Name of the DAX cluster."
  value       = aws_dax_cluster.dax_cluster.cluster_name
}

output "dax_cluster_endpoint" {
  description = "DAX cluster discovery endpoint."
  value       = aws_dax_cluster.dax_cluster.configuration_endpoint
}

output "dax_security_group_id" {
  description = "Security group ID associated with the DAX cluster."
  value       = aws_security_group.dax_sg.id
}
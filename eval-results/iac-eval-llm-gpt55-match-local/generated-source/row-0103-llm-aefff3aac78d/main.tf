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
  region = "us-east-1"
}

variable "eks_cluster_name" {
  description = "Name of the Amazon EKS cluster."
  type        = string
  default     = "example-eks-cluster"
}

variable "eks_cluster_version" {
  description = "Kubernetes version for the Amazon EKS cluster."
  type        = string
  default     = "1.29"
}

resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "eks-vpc"
  }
}

resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "eks-internet-gateway"
  }
}

resource "aws_route_table" "eks_public_route_table" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }

  tags = {
    Name = "eks-public-route-table"
  }
}

resource "aws_subnet" "eks_public_subnet_a" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "eks-public-subnet-a"
  }
}

resource "aws_subnet" "eks_public_subnet_b" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "eks-public-subnet-b"
  }
}

resource "aws_route_table_association" "eks_public_subnet_a_association" {
  subnet_id      = aws_subnet.eks_public_subnet_a.id
  route_table_id = aws_route_table.eks_public_route_table.id
}

resource "aws_route_table_association" "eks_public_subnet_b_association" {
  subnet_id      = aws_subnet.eks_public_subnet_b.id
  route_table_id = aws_route_table.eks_public_route_table.id
}

resource "aws_iam_role" "eks_cluster" {
  name = "eks-cluster"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "eks-cluster"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "eks_cluster" {
  name     = var.eks_cluster_name
  version  = var.eks_cluster_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.eks_public_subnet_a.id,
      aws_subnet.eks_public_subnet_b.id
    ]

    endpoint_private_access = false
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name = var.eks_cluster_name
  }
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.eks_cluster.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint for the EKS cluster."
  value       = aws_eks_cluster.eks_cluster.endpoint
}

output "eks_cluster_role_arn" {
  description = "IAM role ARN used by the EKS cluster."
  value       = aws_iam_role.eks_cluster.arn
}

output "vpc_id" {
  description = "VPC ID used by the EKS cluster."
  value       = aws_vpc.eks_vpc.id
}

output "subnet_ids" {
  description = "Subnet IDs used by the EKS cluster."
  value = [
    aws_subnet.eks_public_subnet_a.id,
    aws_subnet.eks_public_subnet_b.id
  ]
}
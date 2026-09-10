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
  description = "AWS region where the EKS cluster and access entry will be created."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "example"
}

variable "kubernetes_groups" {
  description = "Kubernetes groups to associate with the EKS access entry."
  type        = list(string)
  default     = ["example-group"]
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "example" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "example-eks-vpc"
  }
}

resource "aws_subnet" "example_a" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "example-eks-subnet-a"
  }
}

resource "aws_subnet" "example_b" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "example-eks-subnet-b"
  }
}

resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name = "example-eks-igw"
  }
}

resource "aws_route_table" "example" {
  vpc_id = aws_vpc.example.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example.id
  }

  tags = {
    Name = "example-eks-route-table"
  }
}

resource "aws_route_table_association" "example_a" {
  subnet_id      = aws_subnet.example_a.id
  route_table_id = aws_route_table.example.id
}

resource "aws_route_table_association" "example_b" {
  subnet_id      = aws_subnet.example_b.id
  route_table_id = aws_route_table.example.id
}

resource "aws_iam_role" "eks_cluster" {
  name = "example-eks-cluster-role"

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
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "example" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.29"

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  vpc_config {
    subnet_ids              = [
      aws_subnet.example_a.id,
      aws_subnet.example_b.id
    ]
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name = var.cluster_name
  }
}

resource "aws_iam_role" "eks_access_principal" {
  name = "example-eks-access-principal-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_eks_access_entry" "example" {
  cluster_name      = aws_eks_cluster.example.name
  principal_arn     = aws_iam_role.eks_access_principal.arn
  kubernetes_groups = var.kubernetes_groups
  type              = "STANDARD"

  depends_on = [
    aws_eks_cluster.example
  ]
}
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the EKS cluster will be created."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "example-eks-cluster"
}

variable "namespace" {
  description = "Kubernetes namespace to which the access policy scope is limited."
  type        = string
  default     = "example-namespace"
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

resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name = "example-eks-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.example.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example.id
  }

  tags = {
    Name = "example-eks-public-rt"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "example-eks-public-a"
    "kubernetes.io/role/elb"                   = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "example-eks-public-b"
    "kubernetes.io/role/elb"                   = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
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

resource "aws_iam_role" "eks_access_principal" {
  name = "example-eks-access-principal-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = data.aws_caller_identity.current.arn
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

data "aws_caller_identity" "current" {}

resource "aws_eks_cluster" "example" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.29"

  vpc_config {
    subnet_ids              = [
      aws_subnet.public_a.id,
      aws_subnet.public_b.id
    ]
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_route_table_association.public_a,
    aws_route_table_association.public_b
  ]

  tags = {
    Name = var.cluster_name
  }
}

resource "aws_eks_access_entry" "example" {
  cluster_name  = aws_eks_cluster.example.name
  principal_arn = aws_iam_role.eks_access_principal.arn
  type          = "STANDARD"

  depends_on = [
    aws_eks_cluster.example
  ]
}

resource "aws_eks_access_policy_association" "example" {
  cluster_name  = aws_eks_cluster.example.name
  principal_arn = aws_iam_role.eks_access_principal.arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"

  access_scope {
    type       = "namespace"
    namespaces = [var.namespace]
  }

  depends_on = [
    aws_eks_access_entry.example
  ]
}

output "eks_cluster_name" {
  description = "Name of the created EKS cluster."
  value       = aws_eks_cluster.example.name
}

output "access_policy_association_name" {
  description = "Terraform resource name for the EKS access policy association."
  value       = "example"
}

output "access_principal_arn" {
  description = "IAM principal ARN associated with the EKS access policy."
  value       = aws_iam_role.eks_access_principal.arn
}

output "namespace_access_scope" {
  description = "Namespace to which the EKS access policy is scoped."
  value       = var.namespace
}
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
  description = "AWS region where the EKS cluster will be created."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "example-eks-cluster"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "eks_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

resource "aws_internet_gateway" "eks_igw" {
  vpc_id = aws_vpc.eks_vpc.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_route_table" "eks_public_rt" {
  vpc_id = aws_vpc.eks_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks_igw.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_subnet" "eks_public_subnet_a" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name                                      = "${var.cluster_name}-public-subnet-a"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                 = "1"
  }
}

resource "aws_subnet" "eks_public_subnet_b" {
  vpc_id                  = aws_vpc.eks_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name                                      = "${var.cluster_name}-public-subnet-b"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                 = "1"
  }
}

resource "aws_route_table_association" "eks_public_subnet_a_assoc" {
  subnet_id      = aws_subnet.eks_public_subnet_a.id
  route_table_id = aws_route_table.eks_public_rt.id
}

resource "aws_route_table_association" "eks_public_subnet_b_assoc" {
  subnet_id      = aws_subnet.eks_public_subnet_b.id
  route_table_id = aws_route_table.eks_public_rt.id
}

resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.cluster_name}-cluster-role"

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
    Name = "${var.cluster_name}-cluster-role"
  }
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "eks_service_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSServicePolicy"
}

resource "aws_eks_cluster" "eks_cluster" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = "1.29"

  vpc_config {
    subnet_ids = [
      aws_subnet.eks_public_subnet_a.id,
      aws_subnet.eks_public_subnet_b.id
    ]

    endpoint_public_access  = true
    endpoint_private_access = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_iam_role_policy_attachment.eks_service_policy,
    aws_route_table_association.eks_public_subnet_a_assoc,
    aws_route_table_association.eks_public_subnet_b_assoc
  ]

  provisioner "local-exec" {
    when    = create
    command = "aws eks update-kubeconfig --region ${var.aws_region} --name ${self.name} --alias ${self.name} --user-alias ${self.name}"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl config delete-context ${self.name} || true && kubectl config delete-cluster ${self.name} || true && kubectl config unset users.${self.name} || true"
  }

  tags = {
    Name = var.cluster_name
  }
}

output "cluster_name" {
  description = "The name of the EKS cluster."
  value       = aws_eks_cluster.eks_cluster.name
}

output "cluster_endpoint" {
  description = "The endpoint for the EKS Kubernetes API server."
  value       = aws_eks_cluster.eks_cluster.endpoint
}

output "cluster_arn" {
  description = "The ARN of the EKS cluster."
  value       = aws_eks_cluster.eks_cluster.arn
}

output "vpc_id" {
  description = "The VPC ID used by the EKS cluster."
  value       = aws_vpc.eks_vpc.id
}

output "subnet_ids" {
  description = "Subnet IDs used by the EKS cluster."
  value = [
    aws_subnet.eks_public_subnet_a.id,
    aws_subnet.eks_public_subnet_b.id
  ]
}
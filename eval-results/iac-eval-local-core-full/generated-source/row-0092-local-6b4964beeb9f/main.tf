terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "example" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "example"
  }
}

resource "aws_subnet" "example_a" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "example-a"
  }
}

resource "aws_subnet" "example_b" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "example-b"
  }
}

resource "aws_iam_role" "example" {
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

resource "aws_iam_role_policy_attachment" "example_cluster_policy" {
  role       = aws_iam_role.example.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_user" "example" {
  name = "example"
}

resource "aws_eks_cluster" "example" {
  name     = "example"
  role_arn = aws_iam_role.example.arn
  version  = "1.30"

  access_config {
    authentication_mode = "API"
  }

  vpc_config {
    subnet_ids = [
      aws_subnet.example_a.id,
      aws_subnet.example_b.id,
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.example_cluster_policy,
  ]
}

resource "aws_eks_access_entry" "example" {
  cluster_name  = aws_eks_cluster.example.name
  principal_arn = aws_iam_user.example.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "example" {
  cluster_name  = aws_eks_cluster.example.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  principal_arn = aws_iam_user.example.arn

  access_scope {
    type       = "namespace"
    namespaces = ["example"]
  }

  depends_on = [
    aws_eks_access_entry.example,
  ]
}

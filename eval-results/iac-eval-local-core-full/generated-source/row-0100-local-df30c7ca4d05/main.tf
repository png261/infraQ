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

data "aws_iam_policy_document" "demo_eks" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "demo_eks" {
  name               = "demo_eks"
  assume_role_policy = data.aws_iam_policy_document.demo_eks.json
}

resource "aws_iam_role_policy_attachment" "demo_eks_AmazonEKSClusterPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.demo_eks.name
}

resource "aws_iam_role_policy_attachment" "demo_eks_AmazonEKSVPCResourceController" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
  role       = aws_iam_role.demo_eks.name
}

resource "aws_vpc" "demo_eks" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "demo_eks"
  }
}

resource "aws_subnet" "demo_eks_a" {
  vpc_id                  = aws_vpc.demo_eks.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "demo_eks-a"
  }
}

resource "aws_subnet" "demo_eks_b" {
  vpc_id                  = aws_vpc.demo_eks.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "demo_eks-b"
  }
}

resource "aws_eks_cluster" "demo_eks" {
  name     = "demo_eks"
  role_arn = aws_iam_role.demo_eks.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.demo_eks_a.id,
      aws_subnet.demo_eks_b.id,
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.demo_eks_AmazonEKSClusterPolicy,
    aws_iam_role_policy_attachment.demo_eks_AmazonEKSVPCResourceController,
  ]
}

data "aws_eks_cluster" "demo_eks" {
  name = aws_eks_cluster.demo_eks.name
}

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

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_iam_role" "demo" {
  name = "eks-cluster-demo"

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
    Name = "eks-cluster-demo"
  }
}

resource "aws_iam_role_policy_attachment" "demo_eks_cluster_policy" {
  role       = aws_iam_role.demo.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_vpc" "demo" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "demo-eks-vpc"
  }
}

resource "aws_internet_gateway" "demo" {
  vpc_id = aws_vpc.demo.id

  tags = {
    Name = "demo-eks-igw"
  }
}

resource "aws_route_table" "demo_public" {
  vpc_id = aws_vpc.demo.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.demo.id
  }

  tags = {
    Name = "demo-eks-public-rt"
  }
}

resource "aws_subnet" "demo_public_1" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name                        = "demo-eks-public-subnet-1"
    "kubernetes.io/cluster/demo" = "shared"
    "kubernetes.io/role/elb"     = "1"
  }
}

resource "aws_subnet" "demo_public_2" {
  vpc_id                  = aws_vpc.demo.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name                        = "demo-eks-public-subnet-2"
    "kubernetes.io/cluster/demo" = "shared"
    "kubernetes.io/role/elb"     = "1"
  }
}

resource "aws_route_table_association" "demo_public_1" {
  subnet_id      = aws_subnet.demo_public_1.id
  route_table_id = aws_route_table.demo_public.id
}

resource "aws_route_table_association" "demo_public_2" {
  subnet_id      = aws_subnet.demo_public_2.id
  route_table_id = aws_route_table.demo_public.id
}

resource "aws_eks_cluster" "demo" {
  name     = "demo"
  role_arn = aws_iam_role.demo.arn
  version  = "1.29"

  vpc_config {
    subnet_ids = [
      aws_subnet.demo_public_1.id,
      aws_subnet.demo_public_2.id
    ]

    endpoint_public_access  = true
    endpoint_private_access = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.demo_eks_cluster_policy,
    aws_route_table_association.demo_public_1,
    aws_route_table_association.demo_public_2
  ]

  tags = {
    Name = "demo"
  }
}

output "eks_cluster_name" {
  value = aws_eks_cluster.demo.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.demo.endpoint
}

output "eks_cluster_role_arn" {
  value = aws_iam_role.demo.arn
}

output "eks_cluster_subnet_ids" {
  value = [
    aws_subnet.demo_public_1.id,
    aws_subnet.demo_public_2.id
  ]
}
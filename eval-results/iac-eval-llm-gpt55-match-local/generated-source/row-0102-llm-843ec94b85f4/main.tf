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

resource "aws_vpc" "example" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "example"
  }
}

resource "aws_internet_gateway" "example" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name = "example"
  }
}

resource "aws_route_table" "example_public" {
  vpc_id = aws_vpc.example.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example.id
  }

  tags = {
    Name = "example-public"
  }
}

resource "aws_subnet" "example_public_a" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "example-public-a"
  }
}

resource "aws_subnet" "example_public_b" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "example-public-b"
  }
}

resource "aws_route_table_association" "example_public_a" {
  subnet_id      = aws_subnet.example_public_a.id
  route_table_id = aws_route_table.example_public.id
}

resource "aws_route_table_association" "example_public_b" {
  subnet_id      = aws_subnet.example_public_b.id
  route_table_id = aws_route_table.example_public.id
}

resource "aws_iam_role" "example" {
  name = "example"

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
    Name = "example"
  }
}

resource "aws_iam_role_policy_attachment" "example_eks_cluster_policy" {
  role       = aws_iam_role.example.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "example" {
  name     = "example"
  role_arn = aws_iam_role.example.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.example_public_a.id,
      aws_subnet.example_public_b.id
    ]

    endpoint_private_access = false
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.example_eks_cluster_policy
  ]

  tags = {
    Name = "example"
  }
}

output "eks_cluster_name" {
  value = aws_eks_cluster.example.name
}

output "eks_cluster_endpoint" {
  value = aws_eks_cluster.example.endpoint
}

output "eks_cluster_role_arn" {
  value = aws_iam_role.example.arn
}

output "vpc_id" {
  value = aws_vpc.example.id
}

output "subnet_ids" {
  value = [
    aws_subnet.example_public_a.id,
    aws_subnet.example_public_b.id
  ]
}
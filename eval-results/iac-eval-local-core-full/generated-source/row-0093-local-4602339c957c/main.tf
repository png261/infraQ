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

resource "aws_subnet" "example" {
  count = 2

  vpc_id                  = aws_vpc.example.id
  cidr_block              = cidrsubnet(aws_vpc.example.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "example-eks-subnet-${count.index + 1}"
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

resource "aws_eks_cluster" "example" {
  name     = "example"
  role_arn = aws_iam_role.example.arn

  vpc_config {
    subnet_ids = aws_subnet.example[*].id
  }

  depends_on = [
    aws_iam_role_policy_attachment.example_cluster_policy
  ]
}

resource "aws_eks_addon" "example" {
  cluster_name = aws_eks_cluster.example.name
  addon_name   = "vpc-cni"
}

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
  map_public_ip_on_launch = false

  tags = {
    Name = "example-eks-subnet-a"
  }
}

resource "aws_subnet" "example_b" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "example-eks-subnet-b"
  }
}

data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "example" {
  name               = "example-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json
}

resource "aws_iam_role_policy_attachment" "example_cluster_policy" {
  role       = aws_iam_role.example.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "example" {
  name     = "example"
  role_arn = aws_iam_role.example.arn

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

resource "aws_eks_identity_provider_config" "example" {
  cluster_name = aws_eks_cluster.example.name

  oidc {
    client_id                     = "example-client-id"
    identity_provider_config_name = "example-oidc-provider"
    issuer_url                    = "https://issuer.example.com"
  }
}

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  cluster_name = "iac-eval-eks"
}

resource "aws_vpc" "eks" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.cluster_name}-vpc"
  }
}

resource "aws_subnet" "eks_a" {
  vpc_id                  = aws_vpc.eks.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name                                      = "${local.cluster_name}-subnet-a"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "eks_b" {
  vpc_id                  = aws_vpc.eks.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name                                      = "${local.cluster_name}-subnet-b"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

resource "aws_iam_role" "eks-cluster" {
  name = "${local.cluster_name}-cluster-role"

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

resource "aws_iam_role_policy_attachment" "eks-cluster-policy" {
  role       = aws_iam_role.eks-cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role" "eks-fargate-profile" {
  name = "${local.cluster_name}-fargate-pod-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks-fargate-pods.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks-fargate-profile" {
  role       = aws_iam_role.eks-fargate-profile.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

resource "aws_eks_cluster" "eks" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks-cluster.arn
  version  = "1.29"

  vpc_config {
    subnet_ids = [
      aws_subnet.eks_a.id,
      aws_subnet.eks_b.id,
    ]
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks-cluster-policy,
  ]
}

resource "aws_eks_fargate_profile" "kube-system" {
  cluster_name           = aws_eks_cluster.eks.name
  fargate_profile_name   = "kube-system"
  pod_execution_role_arn = aws_iam_role.eks-fargate-profile.arn
  subnet_ids = [
    aws_subnet.eks_a.id,
    aws_subnet.eks_b.id,
  ]

  selector {
    namespace = "kube-system"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks-fargate-profile,
  ]
}

data "aws_eks_cluster_auth" "eks" {
  name = aws_eks_cluster.eks.name
}

resource "null_resource" "k8s_patcher" {
  triggers = {
    endpoint = aws_eks_cluster.eks.endpoint
    ca_crt   = aws_eks_cluster.eks.certificate_authority[0].data
    token    = data.aws_eks_cluster_auth.eks.token
  }

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]
    command     = <<-EOT
      set -e
      tmp_ca="$(mktemp)"
      printf '%s' '${self.triggers.ca_crt}' | base64 -d > "$tmp_ca"
      kubectl --server='${self.triggers.endpoint}' \
        --certificate-authority="$tmp_ca" \
        --token='${self.triggers.token}' \
        --namespace='kube-system' \
        patch deployment coredns \
        --type='json' \
        -p='[{"op":"replace","path":"/spec/template/metadata/annotations/eks.amazonaws.com~1compute-type","value":"fargate"}]'
      rm -f "$tmp_ca"
    EOT
  }

  lifecycle {
    ignore_changes = [triggers]
  }

  depends_on = [
    aws_eks_fargate_profile.kube-system,
  ]
}

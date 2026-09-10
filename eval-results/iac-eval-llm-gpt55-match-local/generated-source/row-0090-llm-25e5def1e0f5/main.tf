terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    null = {
      source  = "hashicorp/null"
      version = ">= 3.2"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the EKS cluster and related resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "example-fargate-eks-cluster"
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.29"
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  private_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"           = "1"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

resource "aws_vpc" "eks" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

resource "aws_internet_gateway" "eks" {
  vpc_id = aws_vpc.eks.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.eks.id
  cidr_block              = "10.50.0.0/20"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(
    local.public_subnet_tags,
    {
      Name = "${var.cluster_name}-public-a"
    }
  )
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.eks.id
  cidr_block              = "10.50.16.0/20"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = merge(
    local.public_subnet_tags,
    {
      Name = "${var.cluster_name}-public-b"
    }
  )
}

resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.eks.id
  cidr_block              = "10.50.32.0/20"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = merge(
    local.private_subnet_tags,
    {
      Name = "${var.cluster_name}-private-a"
    }
  )
}

resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.eks.id
  cidr_block              = "10.50.48.0/20"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = merge(
    local.private_subnet_tags,
    {
      Name = "${var.cluster_name}-private-b"
    }
  )
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = {
    Name = "${var.cluster_name}-nat-eip"
  }
}

resource "aws_nat_gateway" "eks" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id

  tags = {
    Name = "${var.cluster_name}-nat"
  }

  depends_on = [
    aws_internet_gateway.eks
  ]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.eks.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eks.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.eks.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.eks.id
  }

  tags = {
    Name = "${var.cluster_name}-private-rt"
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

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_iam_role" "eks_cluster" {
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
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.eks_cluster.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.private_a.id,
      aws_subnet.private_b.id
    ]

    endpoint_private_access = true
    endpoint_public_access  = true
  }

  tags = {
    Name = var.cluster_name
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy,
    aws_route_table_association.private_a,
    aws_route_table_association.private_b
  ]
}

resource "aws_iam_role" "fargate_pod_execution" {
  name = "${var.cluster_name}-fargate-pod-execution-role"

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

  tags = {
    Name = "${var.cluster_name}-fargate-pod-execution-role"
  }
}

resource "aws_iam_role_policy_attachment" "fargate_pod_execution_policy" {
  role       = aws_iam_role.fargate_pod_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

resource "aws_eks_fargate_profile" "kube_system" {
  cluster_name           = aws_eks_cluster.this.name
  fargate_profile_name   = "kube-system"
  pod_execution_role_arn = aws_iam_role.fargate_pod_execution.arn

  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  selector {
    namespace = "kube-system"
  }

  tags = {
    Name = "${var.cluster_name}-kube-system-fargate-profile"
  }

  depends_on = [
    aws_iam_role_policy_attachment.fargate_pod_execution_policy,
    aws_eks_cluster.this
  ]
}

data "aws_eks_cluster" "this" {
  name = aws_eks_cluster.this.name

  depends_on = [
    aws_eks_cluster.this
  ]
}

data "aws_eks_cluster_auth" "this" {
  name = aws_eks_cluster.this.name

  depends_on = [
    aws_eks_cluster.this
  ]
}

resource "null_resource" "patch_coredns_for_fargate" {
  triggers = {
    cluster_name     = aws_eks_cluster.this.name
    cluster_endpoint = data.aws_eks_cluster.this.endpoint
    cluster_ca       = data.aws_eks_cluster.this.certificate_authority[0].data
    fargate_profile  = aws_eks_fargate_profile.kube_system.arn
  }

  provisioner "local-exec" {
    interpreter = ["/bin/sh", "-c"]

    command = <<-EOT
      set -e

      KUBECONFIG_FILE="$(mktemp)"

      cat > "$KUBECONFIG_FILE" <<EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: ${data.aws_eks_cluster.this.endpoint}
    certificate-authority-data: ${data.aws_eks_cluster.this.certificate_authority[0].data}
  name: ${aws_eks_cluster.this.name}
contexts:
- context:
    cluster: ${aws_eks_cluster.this.name}
    user: ${aws_eks_cluster.this.name}
  name: ${aws_eks_cluster.this.name}
current-context: ${aws_eks_cluster.this.name}
users:
- name: ${aws_eks_cluster.this.name}
  user:
    token: ${data.aws_eks_cluster_auth.this.token}
EOF

      kubectl --kubeconfig "$KUBECONFIG_FILE" \
        -n kube-system \
        patch deployment coredns \
        --type json \
        -p='[{"op":"remove","path":"/spec/template/metadata/annotations/eks.amazonaws.com~1compute-type"}]' || true

      kubectl --kubeconfig "$KUBECONFIG_FILE" \
        -n kube-system \
        rollout restart deployment coredns

      rm -f "$KUBECONFIG_FILE"
    EOT
  }

  depends_on = [
    aws_eks_fargate_profile.kube_system
  ]
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.this.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint of the EKS cluster."
  value       = aws_eks_cluster.this.endpoint
}

output "eks_cluster_certificate_authority_data" {
  description = "Base64-encoded certificate authority data for the EKS cluster."
  value       = aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "fargate_pod_execution_role_arn" {
  description = "ARN of the IAM role used by EKS Fargate pods."
  value       = aws_iam_role.fargate_pod_execution.arn
}

output "kube_system_fargate_profile_name" {
  description = "Name of the EKS Fargate profile for the kube-system namespace."
  value       = aws_eks_fargate_profile.kube_system.fargate_profile_name
}
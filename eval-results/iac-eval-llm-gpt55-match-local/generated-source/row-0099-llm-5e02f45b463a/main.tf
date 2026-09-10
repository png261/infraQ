terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.34.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the EKS cluster will be deployed."
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "Name of the EKS cluster."
  type        = string
  default     = "example"
}

variable "pod_namespace" {
  description = "Kubernetes namespace for the pod identity association."
  type        = string
  default     = "default"
}

variable "pod_service_account" {
  description = "Kubernetes service account for the pod identity association."
  type        = string
  default     = "example-service-account"
}

data "aws_availability_zones" "available" {
  state = "available"
}

# -------------------------
# Networking
# -------------------------

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

resource "aws_subnet" "example_a" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "example-eks-subnet-a"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

resource "aws_subnet" "example_b" {
  vpc_id                  = aws_vpc.example.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "example-eks-subnet-b"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                    = "1"
  }
}

resource "aws_route_table" "example" {
  vpc_id = aws_vpc.example.id

  tags = {
    Name = "example-eks-public-rt"
  }
}

resource "aws_route" "internet" {
  route_table_id         = aws_route_table.example.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.example.id
}

resource "aws_route_table_association" "example_a" {
  subnet_id      = aws_subnet.example_a.id
  route_table_id = aws_route_table.example.id
}

resource "aws_route_table_association" "example_b" {
  subnet_id      = aws_subnet.example_b.id
  route_table_id = aws_route_table.example.id
}

# -------------------------
# EKS Cluster IAM Role
# -------------------------

data "aws_iam_policy_document" "eks_cluster_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "example-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_cluster_assume_role.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# -------------------------
# EKS Cluster
# -------------------------

resource "aws_eks_cluster" "example" {
  name     = var.cluster_name
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.29"

  vpc_config {
    subnet_ids              = [
      aws_subnet.example_a.id,
      aws_subnet.example_b.id
    ]
    endpoint_public_access  = true
    endpoint_private_access = false
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  tags = {
    Name = var.cluster_name
  }
}

# -------------------------
# EKS Node Group IAM Role
# -------------------------

data "aws_iam_policy_document" "eks_node_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eks_node" {
  name               = "example-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.eks_node_assume_role.json
}

resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "eks_container_registry_read_only" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# -------------------------
# EKS Managed Node Group
# -------------------------

resource "aws_eks_node_group" "example" {
  cluster_name    = aws_eks_cluster.example.name
  node_group_name = "example-node-group"
  node_role_arn   = aws_iam_role.eks_node.arn

  subnet_ids = [
    aws_subnet.example_a.id,
    aws_subnet.example_b.id
  ]

  instance_types = ["t3.medium"]

  scaling_config {
    desired_size = 2
    min_size     = 1
    max_size     = 3
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_container_registry_read_only
  ]

  tags = {
    Name = "example-node-group"
  }
}

# -------------------------
# EKS Pod Identity Add-on
# -------------------------

resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.example.name
  addon_name   = "eks-pod-identity-agent"

  depends_on = [
    aws_eks_node_group.example
  ]
}

# -------------------------
# IAM Policy Document for EKS Pod Identity
# Called "example"
# -------------------------

data "aws_iam_policy_document" "example" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }

    actions = [
      "sts:AssumeRole",
      "sts:TagSession"
    ]
  }
}

# -------------------------
# IAM Role for EKS Pods
# Called "example"
# -------------------------

resource "aws_iam_role" "example" {
  name               = "example-eks-pod-identity-role"
  assume_role_policy = data.aws_iam_policy_document.example.json

  tags = {
    Name = "example-eks-pod-identity-role"
  }
}

# Attach S3 read-only access to the pod identity role
resource "aws_iam_role_policy_attachment" "example_s3_read_only" {
  role       = aws_iam_role.example.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

# -------------------------
# EKS Pod Identity Association
# -------------------------

resource "aws_eks_pod_identity_association" "example" {
  cluster_name    = aws_eks_cluster.example.name
  namespace       = var.pod_namespace
  service_account = var.pod_service_account
  role_arn        = aws_iam_role.example.arn

  depends_on = [
    aws_eks_addon.pod_identity_agent,
    aws_iam_role_policy_attachment.example_s3_read_only
  ]

  tags = {
    Name = "example-pod-identity-association"
  }
}

# -------------------------
# Outputs
# -------------------------

output "eks_cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.example.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint for the EKS cluster."
  value       = aws_eks_cluster.example.endpoint
}

output "pod_identity_role_arn" {
  description = "IAM role ARN associated with the Kubernetes service account."
  value       = aws_iam_role.example.arn
}

output "pod_identity_association_id" {
  description = "ID of the EKS Pod Identity Association."
  value       = aws_eks_pod_identity_association.example.association_id
}
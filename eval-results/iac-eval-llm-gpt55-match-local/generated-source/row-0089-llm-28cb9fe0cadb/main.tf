terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.25.0"
    }

    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.aws_tags
  }
}

variable "aws_region" {
  description = "AWS region where resources will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix used for naming AWS resources."
  type        = string
  default     = "terraformai"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "dev"
}

variable "ecr_repository_name" {
  description = "Name of the ECR repository to optionally query for the stable image."
  type        = string
  default     = "example-app"
}

variable "fetch_stable_ecr_image" {
  description = "Whether to fetch the ECR image tagged stable from the repository."
  type        = bool
  default     = false
}

variable "eks_cluster_version" {
  description = "Kubernetes version for the EKS cluster."
  type        = string
  default     = "1.29"
}

variable "eks_node_instance_types" {
  description = "EC2 instance types for EKS managed node groups."
  type        = list(string)
  default     = ["t3.medium"]
}

variable "eks_node_min_size" {
  description = "Minimum number of EKS worker nodes."
  type        = number
  default     = 1
}

variable "eks_node_desired_size" {
  description = "Desired number of EKS worker nodes."
  type        = number
  default     = 2
}

variable "eks_node_max_size" {
  description = "Maximum number of EKS worker nodes."
  type        = number
  default     = 3
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ecr_image" "stable" {
  count = var.fetch_stable_ecr_image ? 1 : 0

  repository_name = var.ecr_repository_name
  image_tag       = "stable"
}

locals {
  workspace_name = terraform.workspace

  cluster_name = "${var.name_prefix}-${var.environment}-${local.workspace_name}-eks"

  image_tag = "stable"

  stable_ecr_image_digest = var.fetch_stable_ecr_image ? data.aws_ecr_image.stable[0].image_digest : null

  stable_ecr_image_uri = var.fetch_stable_ecr_image ? "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${var.ecr_repository_name}@${data.aws_ecr_image.stable[0].image_digest}" : null

  aws_tags = {
    Project     = var.name_prefix
    Environment = var.environment
    Workspace   = terraform.workspace
    ManagedBy   = "Terraform"
    Owner       = "TerraformAI"
  }
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"

  name = "${local.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  private_subnets = [
    "10.0.1.0/24",
    "10.0.2.0/24",
    "10.0.3.0/24"
  ]

  public_subnets = [
    "10.0.101.0/24",
    "10.0.102.0/24",
    "10.0.103.0/24"
  ]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
  }

  tags = local.aws_tags
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.8.5"

  cluster_name    = local.cluster_name
  cluster_version = var.eks_cluster_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  enable_cluster_creator_admin_permissions = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    coredns = {
      most_recent = true
    }

    kube-proxy = {
      most_recent = true
    }

    vpc-cni = {
      most_recent = true
    }

    aws-ebs-csi-driver = {
      most_recent = true
    }
  }

  eks_managed_node_groups = {
    default = {
      name = "${local.cluster_name}-default-ng"

      instance_types = var.eks_node_instance_types

      min_size     = var.eks_node_min_size
      desired_size = var.eks_node_desired_size
      max_size     = var.eks_node_max_size

      capacity_type = "ON_DEMAND"

      iam_role_additional_policies = {
        AmazonEBSCSIDriverPolicy = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
        AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }

      labels = {
        Environment = var.environment
        NodeGroup   = "default"
      }

      tags = local.aws_tags
    }
  }

  tags = local.aws_tags
}

data "aws_eks_cluster" "this" {
  name = module.eks.cluster_name

  depends_on = [
    module.eks
  ]
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name

  depends_on = [
    module.eks
  ]
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

output "aws_account_id" {
  description = "AWS account ID of the current caller."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_caller_arn" {
  description = "ARN of the current AWS caller identity."
  value       = data.aws_caller_identity.current.arn
}

output "workspace_name" {
  description = "Terraform workspace name."
  value       = local.workspace_name
}

output "eks_cluster_name" {
  description = "Name of the created EKS cluster."
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Endpoint URL for the created EKS cluster."
  value       = data.aws_eks_cluster.this.endpoint
}

output "eks_cluster_version" {
  description = "Kubernetes version of the created EKS cluster."
  value       = data.aws_eks_cluster.this.version
}

output "stable_image_tag" {
  description = "Configured stable image tag."
  value       = local.image_tag
}

output "stable_ecr_image_digest" {
  description = "Digest of the ECR image tagged stable if lookup is enabled."
  value       = local.stable_ecr_image_digest
}

output "stable_ecr_image_uri" {
  description = "Fully qualified stable ECR image URI if lookup is enabled."
  value       = local.stable_ecr_image_uri
}
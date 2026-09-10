provider "aws" {
  region = var.region

  default_tags {
    tags = local.provider_tags
  }
}

data "aws_region" "current" {}

data "aws_caller_identity" "current" {}

data "aws_ecr_image" "stable" {
  repository_name = var.ecr_repository_name
  image_tag       = local.image_tag
}

locals {
  image_tag      = "stable"
  workspace_name = terraform.workspace
  name           = "${var.name_prefix}-${local.workspace_name}"

  provider_tags = {
    Project   = "iac-eval"
    Benchmark = "eks"
    Workspace = local.workspace_name
    ManagedBy = "terraform"
  }

  aws_tags = merge(local.provider_tags, {
    AccountId = data.aws_caller_identity.current.account_id
    Region    = data.aws_region.current.name
  })
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.37.2"

  cluster_name    = local.name
  cluster_version = var.cluster_version

  cluster_endpoint_public_access = true
  enable_irsa                    = true

  vpc_id     = aws_vpc.this.id
  subnet_ids = aws_subnet.public[*].id

  eks_managed_node_groups = {
    default = {
      subnet_ids                  = aws_subnet.public[*].id
      instance_types              = var.node_instance_types
      min_size                    = var.node_count
      max_size                    = var.node_count
      desired_size                = var.node_count
      associate_public_ip_address = true

      iam_role_additional_policies = {
        AmazonEC2ContainerRegistryReadOnly = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
      }
    }
  }

  tags = local.aws_tags
}

data "aws_eks_cluster" "aptos" {
  name = module.eks.cluster_name

  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "aptos" {
  name = module.eks.cluster_name
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.aptos.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.aptos.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.aptos.token
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.aptos.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.aptos.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.aptos.token
}

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
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the EKS cluster exists."
  type        = string
  default     = "us-east-1"
}

variable "eks_cluster_name" {
  description = "Name of the existing EKS cluster."
  type        = string
  default     = "example"
}

variable "oidc_client_id" {
  description = "OIDC client ID to use for the EKS identity provider configuration."
  type        = string
  default     = "example-client-id"
}

variable "oidc_identity_provider_config_name" {
  description = "Name of the OIDC identity provider configuration for EKS."
  type        = string
  default     = "example-oidc-provider"
}

variable "oidc_issuer_url" {
  description = "Issuer URL for the external OIDC identity provider."
  type        = string
  default     = "https://issuer.example.com"
}

data "aws_eks_cluster" "example" {
  name = var.eks_cluster_name
}

resource "aws_eks_identity_provider_config" "example_oidc" {
  cluster_name = data.aws_eks_cluster.example.name

  oidc {
    client_id                     = var.oidc_client_id
    identity_provider_config_name = var.oidc_identity_provider_config_name
    issuer_url                    = var.oidc_issuer_url

    username_claim = "sub"
    groups_claim   = "groups"
  }

  tags = {
    Name        = var.oidc_identity_provider_config_name
    Environment = "example"
    ManagedBy   = "terraform"
  }
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster."
  value       = data.aws_eks_cluster.example.name
}

output "oidc_identity_provider_config_name" {
  description = "Name of the configured OIDC identity provider."
  value       = aws_eks_identity_provider_config.example_oidc.oidc[0].identity_provider_config_name
}

output "oidc_issuer_url" {
  description = "Issuer URL used by the OIDC identity provider."
  value       = aws_eks_identity_provider_config.example_oidc.oidc[0].issuer_url
}
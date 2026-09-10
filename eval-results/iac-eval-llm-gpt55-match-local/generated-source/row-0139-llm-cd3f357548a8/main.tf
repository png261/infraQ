terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the Redshift cluster will be created."
  type        = string
  default     = "us-east-1"
}

variable "redshift_cluster_identifier" {
  description = "Identifier for the Redshift cluster."
  type        = string
  default     = "single-node-redshift-cluster"
}

variable "redshift_database_name" {
  description = "Initial database name for the Redshift cluster."
  type        = string
  default     = "dev"
}

variable "redshift_master_username" {
  description = "Master username for the Redshift cluster."
  type        = string
  default     = "adminuser"
}

variable "redshift_master_password" {
  description = "Master password for the Redshift cluster."
  type        = string
  sensitive   = true
  default     = "ChangeMe12345!"
}

variable "redshift_node_type" {
  description = "Node type for the Redshift cluster."
  type        = string
  default     = "dc2.large"
}

resource "aws_redshift_cluster" "single_node" {
  cluster_identifier = var.redshift_cluster_identifier
  database_name      = var.redshift_database_name
  master_username    = var.redshift_master_username
  master_password    = var.redshift_master_password

  node_type    = var.redshift_node_type
  cluster_type = "single-node"

  publicly_accessible = false
  encrypted           = true

  skip_final_snapshot = true

  tags = {
    Name        = "single-node-redshift-cluster"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

output "redshift_cluster_id" {
  description = "The ID of the Redshift cluster."
  value       = aws_redshift_cluster.single_node.id
}

output "redshift_cluster_endpoint" {
  description = "The connection endpoint of the Redshift cluster."
  value       = aws_redshift_cluster.single_node.endpoint
}
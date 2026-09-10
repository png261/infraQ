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
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the Redshift VPC."
  type        = string
  default     = "10.50.0.0/16"
}

variable "subnet_a_cidr" {
  description = "CIDR block for the first private subnet."
  type        = string
  default     = "10.50.1.0/24"
}

variable "subnet_b_cidr" {
  description = "CIDR block for the second private subnet."
  type        = string
  default     = "10.50.2.0/24"
}

variable "redshift_cluster_identifier" {
  description = "Identifier for the Redshift cluster."
  type        = string
  default     = "example-redshift-cluster"
}

variable "redshift_database_name" {
  description = "Initial database name for Redshift."
  type        = string
  default     = "dev"
}

variable "redshift_master_username" {
  description = "Master username for Redshift."
  type        = string
  default     = "adminuser"
}

variable "redshift_master_password" {
  description = "Master password for Redshift. Must be at least 8 characters and contain uppercase, lowercase, and numbers."
  type        = string
  sensitive   = true
  default     = "RedshiftPass123"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "redshift_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "redshift-endpoint-vpc"
  }
}

resource "aws_subnet" "redshift_subnet_a" {
  vpc_id                  = aws_vpc.redshift_vpc.id
  cidr_block              = var.subnet_a_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "redshift-private-subnet-a"
  }
}

resource "aws_subnet" "redshift_subnet_b" {
  vpc_id                  = aws_vpc.redshift_vpc.id
  cidr_block              = var.subnet_b_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "redshift-private-subnet-b"
  }
}

resource "aws_redshift_subnet_group" "redshift_subnet_group" {
  name        = "redshift-two-subnet-group"
  description = "Redshift subnet group spanning two private subnets"

  subnet_ids = [
    aws_subnet.redshift_subnet_a.id,
    aws_subnet.redshift_subnet_b.id
  ]

  tags = {
    Name = "redshift-two-subnet-group"
  }
}

resource "aws_security_group" "redshift_cluster_sg" {
  name        = "redshift-cluster-sg"
  description = "Security group for the Redshift cluster"
  vpc_id      = aws_vpc.redshift_vpc.id

  ingress {
    description = "Allow Redshift access from within the VPC"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "redshift-cluster-sg"
  }
}

resource "aws_security_group" "redshift_endpoint_sg" {
  name        = "redshift-endpoint-access-sg"
  description = "Security group for Redshift-managed endpoint access"
  vpc_id      = aws_vpc.redshift_vpc.id

  ingress {
    description = "Allow Redshift endpoint access from within the VPC"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "redshift-endpoint-access-sg"
  }
}

resource "aws_redshift_cluster" "redshift_cluster" {
  cluster_identifier        = var.redshift_cluster_identifier
  database_name             = var.redshift_database_name
  master_username           = var.redshift_master_username
  master_password           = var.redshift_master_password
  node_type                 = "ra3.xlplus"
  cluster_type              = "multi-node"
  number_of_nodes           = 2
  port                      = 5439
  publicly_accessible       = false
  encrypted                 = true
  enhanced_vpc_routing      = true
  skip_final_snapshot       = true
  cluster_subnet_group_name = aws_redshift_subnet_group.redshift_subnet_group.name

  vpc_security_group_ids = [
    aws_security_group.redshift_cluster_sg.id
  ]

  tags = {
    Name = "example-redshift-cluster"
  }
}

resource "aws_redshift_endpoint_access" "redshift_endpoint_access" {
  endpoint_name          = "redshift-private-endpoint"
  cluster_identifier    = aws_redshift_cluster.redshift_cluster.cluster_identifier
  subnet_group_name     = aws_redshift_subnet_group.redshift_subnet_group.name
  vpc_security_group_ids = [aws_security_group.redshift_endpoint_sg.id]

  depends_on = [
    aws_redshift_cluster.redshift_cluster
  ]
}

output "redshift_cluster_identifier" {
  description = "The Redshift cluster identifier."
  value       = aws_redshift_cluster.redshift_cluster.cluster_identifier
}

output "redshift_cluster_endpoint" {
  description = "The standard Redshift cluster endpoint."
  value       = aws_redshift_cluster.redshift_cluster.endpoint
}

output "redshift_endpoint_access_name" {
  description = "The Redshift-managed endpoint access name."
  value       = aws_redshift_endpoint_access.redshift_endpoint_access.endpoint_name
}

output "redshift_endpoint_address" {
  description = "The Redshift-managed endpoint DNS address."
  value       = aws_redshift_endpoint_access.redshift_endpoint_access.address
}

output "redshift_endpoint_port" {
  description = "The Redshift-managed endpoint port."
  value       = aws_redshift_endpoint_access.redshift_endpoint_access.port
}
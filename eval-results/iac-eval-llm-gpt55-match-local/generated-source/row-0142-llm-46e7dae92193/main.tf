terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy the Redshift cluster into."
  type        = string
  default     = "us-east-1"
}

variable "cluster_identifier" {
  description = "Identifier for the Redshift cluster."
  type        = string
  default     = "single-node-redshift-cluster"
}

variable "database_name" {
  description = "Initial database name for the Redshift cluster."
  type        = string
  default     = "dev"
}

variable "master_username" {
  description = "Master username for the Redshift cluster."
  type        = string
  default     = "adminuser"
}

variable "node_type" {
  description = "Redshift node type."
  type        = string
  default     = "dc2.large"
}

variable "automated_snapshot_retention_days" {
  description = "Number of days to retain automated Redshift snapshots."
  type        = number
  default     = 7
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "random_password" "redshift_master_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_vpc" "redshift_vpc" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "redshift-vpc"
  }
}

resource "aws_internet_gateway" "redshift_igw" {
  vpc_id = aws_vpc.redshift_vpc.id

  tags = {
    Name = "redshift-igw"
  }
}

resource "aws_subnet" "redshift_subnet_a" {
  vpc_id                  = aws_vpc.redshift_vpc.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "redshift-subnet-a"
  }
}

resource "aws_subnet" "redshift_subnet_b" {
  vpc_id                  = aws_vpc.redshift_vpc.id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "redshift-subnet-b"
  }
}

resource "aws_route_table" "redshift_route_table" {
  vpc_id = aws_vpc.redshift_vpc.id

  tags = {
    Name = "redshift-route-table"
  }
}

resource "aws_route_table_association" "redshift_subnet_a_assoc" {
  subnet_id      = aws_subnet.redshift_subnet_a.id
  route_table_id = aws_route_table.redshift_route_table.id
}

resource "aws_route_table_association" "redshift_subnet_b_assoc" {
  subnet_id      = aws_subnet.redshift_subnet_b.id
  route_table_id = aws_route_table.redshift_route_table.id
}

resource "aws_security_group" "redshift_sg" {
  name        = "redshift-security-group"
  description = "Security group for the single-node Redshift cluster"
  vpc_id      = aws_vpc.redshift_vpc.id

  ingress {
    description = "Allow Redshift access from within the VPC"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.redshift_vpc.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "redshift-security-group"
  }
}

resource "aws_redshift_subnet_group" "redshift_subnet_group" {
  name        = "redshift-subnet-group"
  description = "Subnet group for the single-node Redshift cluster"

  subnet_ids = [
    aws_subnet.redshift_subnet_a.id,
    aws_subnet.redshift_subnet_b.id
  ]

  tags = {
    Name = "redshift-subnet-group"
  }
}

resource "aws_redshift_snapshot_schedule" "every_12_hours" {
  identifier  = "redshift-snapshot-every-12-hours"
  description = "Create an automated Redshift snapshot every 12 hours"

  definitions = [
    "rate(12 hours)"
  ]

  tags = {
    Name = "redshift-snapshot-every-12-hours"
  }
}

resource "aws_redshift_cluster" "single_node" {
  cluster_identifier = var.cluster_identifier
  database_name      = var.database_name

  cluster_type = "single-node"
  node_type    = var.node_type

  master_username = var.master_username
  master_password = random_password.redshift_master_password.result

  port = 5439

  vpc_security_group_ids = [
    aws_security_group.redshift_sg.id
  ]

  cluster_subnet_group_name = aws_redshift_subnet_group.redshift_subnet_group.name

  publicly_accessible = false
  encrypted           = true

  automated_snapshot_retention_period = var.automated_snapshot_retention_days

  skip_final_snapshot = true

  tags = {
    Name = var.cluster_identifier
  }
}

resource "aws_redshift_snapshot_schedule_association" "cluster_schedule_association" {
  cluster_identifier  = aws_redshift_cluster.single_node.cluster_identifier
  schedule_identifier = aws_redshift_snapshot_schedule.every_12_hours.identifier
}

output "redshift_cluster_identifier" {
  description = "The Redshift cluster identifier."
  value       = aws_redshift_cluster.single_node.cluster_identifier
}

output "redshift_endpoint" {
  description = "The Redshift cluster endpoint."
  value       = aws_redshift_cluster.single_node.endpoint
}

output "redshift_database_name" {
  description = "The initial Redshift database name."
  value       = aws_redshift_cluster.single_node.database_name
}

output "redshift_master_username" {
  description = "The Redshift master username."
  value       = aws_redshift_cluster.single_node.master_username
}

output "redshift_master_password" {
  description = "The generated Redshift master password."
  value       = random_password.redshift_master_password.result
  sensitive   = true
}
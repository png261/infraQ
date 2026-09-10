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
  region = "us-east-1"
}

provider "aws" {
  alias  = "replica"
  region = "us-east-2"
}

variable "redshift_cluster_identifier" {
  description = "Identifier for the primary Redshift cluster."
  type        = string
  default     = "primary-redshift-cluster"
}

variable "redshift_database_name" {
  description = "Initial database name for Redshift."
  type        = string
  default     = "analytics"
}

variable "redshift_master_username" {
  description = "Master username for Redshift."
  type        = string
  default     = "adminuser"
}

variable "redshift_master_password" {
  description = "Master password for Redshift."
  type        = string
  sensitive   = true
  default     = "ChangeMe12345!"
}

variable "redshift_node_type" {
  description = "Redshift node type."
  type        = string
  default     = "dc2.large"
}

variable "redshift_number_of_nodes" {
  description = "Number of Redshift nodes."
  type        = number
  default     = 2
}

variable "primary_allowed_cidr" {
  description = "CIDR block allowed to connect to Redshift in us-east-1."
  type        = string
  default     = "10.0.0.0/8"
}

data "aws_vpc" "primary_default" {
  default = true
}

data "aws_subnets" "primary_default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary_default.id]
  }
}

data "aws_vpc" "replica_default" {
  provider = aws.replica
  default  = true
}

data "aws_subnets" "replica_default" {
  provider = aws.replica

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.replica_default.id]
  }
}

resource "aws_iam_role" "redshift_role" {
  name = "redshift-cluster-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "redshift.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "redshift_s3_readonly" {
  role       = aws_iam_role.redshift_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_security_group" "primary_redshift" {
  name        = "primary-redshift-sg"
  description = "Security group for primary Redshift cluster"
  vpc_id      = data.aws_vpc.primary_default.id

  ingress {
    description = "Allow Redshift access"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [var.primary_allowed_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "primary-redshift-sg"
  }
}

resource "aws_security_group" "replica_redshift" {
  provider = aws.replica

  name        = "replica-redshift-sg"
  description = "Security group placeholder for replicated Redshift recovery environment"
  vpc_id      = data.aws_vpc.replica_default.id

  ingress {
    description = "Allow Redshift access"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [var.primary_allowed_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "replica-redshift-sg"
  }
}

resource "aws_redshift_subnet_group" "primary" {
  name       = "primary-redshift-subnet-group"
  subnet_ids = data.aws_subnets.primary_default.ids

  tags = {
    Name = "primary-redshift-subnet-group"
  }
}

resource "aws_redshift_subnet_group" "replica" {
  provider = aws.replica

  name       = "replica-redshift-subnet-group"
  subnet_ids = data.aws_subnets.replica_default.ids

  tags = {
    Name = "replica-redshift-subnet-group"
  }
}

resource "aws_redshift_cluster" "primary" {
  cluster_identifier = var.redshift_cluster_identifier
  database_name      = var.redshift_database_name

  master_username = var.redshift_master_username
  master_password = var.redshift_master_password

  node_type       = var.redshift_node_type
  cluster_type    = "multi-node"
  number_of_nodes = var.redshift_number_of_nodes

  port                   = 5439
  publicly_accessible    = false
  encrypted              = false
  enhanced_vpc_routing   = true
  skip_final_snapshot    = true
  apply_immediately      = true
  allow_version_upgrade  = true
  automated_snapshot_retention_period = 7
  preferred_maintenance_window        = "sun:05:00-sun:06:00"

  cluster_subnet_group_name = aws_redshift_subnet_group.primary.name
  vpc_security_group_ids    = [aws_security_group.primary_redshift.id]

  iam_roles = [
    aws_iam_role.redshift_role.arn
  ]

  depends_on = [
    aws_iam_role_policy_attachment.redshift_s3_readonly
  ]

  tags = {
    Name        = "primary-redshift-cluster"
    Environment = "production"
    Region      = "us-east-1"
  }
}

resource "aws_redshift_snapshot_copy" "primary_to_us_east_2" {
  cluster_identifier          = aws_redshift_cluster.primary.cluster_identifier
  destination_region          = "us-east-2"
  retention_period            = 7
  manual_snapshot_retention_period = 7

  depends_on = [
    aws_redshift_cluster.primary
  ]
}

output "primary_redshift_cluster_id" {
  description = "Primary Redshift cluster identifier."
  value       = aws_redshift_cluster.primary.id
}

output "primary_redshift_endpoint" {
  description = "Primary Redshift endpoint address."
  value       = aws_redshift_cluster.primary.endpoint
}

output "primary_redshift_port" {
  description = "Primary Redshift port."
  value       = aws_redshift_cluster.primary.port
}

output "snapshot_replication_destination_region" {
  description = "Region where automated Redshift snapshots are copied for replication."
  value       = aws_redshift_snapshot_copy.primary_to_us_east_2.destination_region
}

output "replica_recovery_subnet_group" {
  description = "Subnet group in us-east-2 prepared for restoring replicated Redshift snapshots."
  value       = aws_redshift_subnet_group.replica.name
}
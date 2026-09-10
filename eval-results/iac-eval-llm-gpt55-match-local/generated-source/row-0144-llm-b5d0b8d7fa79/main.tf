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
  region = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "ha-redshift"
}

variable "redshift_database_name" {
  description = "Initial Redshift database name."
  type        = string
  default     = "analytics"
}

variable "redshift_master_username" {
  description = "Master username for the Redshift cluster."
  type        = string
  default     = "adminuser"
}

variable "redshift_node_type" {
  description = "Redshift node type. Multi-AZ Redshift requires RA3 node types."
  type        = string
  default     = "ra3.4xlarge"
}

variable "redshift_number_of_nodes" {
  description = "Number of Redshift compute nodes."
  type        = number
  default     = 2
}

variable "allowed_redshift_cidr" {
  description = "CIDR block allowed to connect to Redshift."
  type        = string
  default     = "10.0.0.0/16"
}

resource "random_password" "redshift_master_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_subnet" "redshift_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-subnet-us-east-1a"
  }
}

resource "aws_subnet" "redshift_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-subnet-us-east-1b"
  }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-route-table"
  }
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.main.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "redshift_a" {
  subnet_id      = aws_subnet.redshift_a.id
  route_table_id = aws_route_table.main.id
}

resource "aws_route_table_association" "redshift_b" {
  subnet_id      = aws_subnet.redshift_b.id
  route_table_id = aws_route_table.main.id
}

resource "aws_security_group" "redshift" {
  name        = "${var.project_name}-sg"
  description = "Security group for Amazon Redshift"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow Redshift access from configured CIDR"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [var.allowed_redshift_cidr]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

resource "aws_redshift_subnet_group" "main" {
  name        = "${var.project_name}-subnet-group"
  description = "Redshift subnet group across us-east-1a and us-east-1b"

  subnet_ids = [
    aws_subnet.redshift_a.id,
    aws_subnet.redshift_b.id
  ]

  tags = {
    Name = "${var.project_name}-subnet-group"
  }
}

resource "aws_redshift_parameter_group" "main" {
  name        = "${var.project_name}-parameter-group"
  family      = "redshift-1.0"
  description = "Parameter group for highly available Redshift cluster"

  parameter {
    name  = "enable_user_activity_logging"
    value = "true"
  }

  tags = {
    Name = "${var.project_name}-parameter-group"
  }
}

resource "aws_iam_role" "redshift" {
  name = "${var.project_name}-redshift-role"

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

  tags = {
    Name = "${var.project_name}-redshift-role"
  }
}

resource "aws_iam_role_policy" "redshift_s3_readonly" {
  name = "${var.project_name}-s3-readonly-policy"
  role = aws_iam_role.redshift.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = [
          "arn:aws:s3:::*",
          "arn:aws:s3:::*/*"
        ]
      }
    ]
  })
}

resource "aws_redshift_cluster" "main" {
  cluster_identifier = "${var.project_name}-cluster"

  database_name   = var.redshift_database_name
  master_username = var.redshift_master_username
  master_password = random_password.redshift_master_password.result

  node_type       = var.redshift_node_type
  cluster_type    = "multi-node"
  number_of_nodes = var.redshift_number_of_nodes

  port = 5439

  cluster_subnet_group_name = aws_redshift_subnet_group.main.name
  vpc_security_group_ids    = [aws_security_group.redshift.id]

  cluster_parameter_group_name = aws_redshift_parameter_group.main.name

  publicly_accessible = false
  encrypted           = true

  enhanced_vpc_routing = true

  multi_az = true

  automated_snapshot_retention_period = 7
  preferred_maintenance_window        = "sun:05:00-sun:06:00"

  skip_final_snapshot = true

  iam_roles = [
    aws_iam_role.redshift.arn
  ]

  depends_on = [
    aws_route_table_association.redshift_a,
    aws_route_table_association.redshift_b,
    aws_iam_role_policy.redshift_s3_readonly
  ]

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

output "redshift_cluster_identifier" {
  description = "Redshift cluster identifier."
  value       = aws_redshift_cluster.main.cluster_identifier
}

output "redshift_endpoint" {
  description = "Redshift cluster endpoint."
  value       = aws_redshift_cluster.main.endpoint
}

output "redshift_database_name" {
  description = "Redshift database name."
  value       = aws_redshift_cluster.main.database_name
}

output "redshift_master_username" {
  description = "Redshift master username."
  value       = aws_redshift_cluster.main.master_username
}

output "redshift_master_password" {
  description = "Generated Redshift master password."
  value       = random_password.redshift_master_password.result
  sensitive   = true
}
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
  type        = string
  description = "AWS region where the Redshift cluster will be deployed."
  default     = "us-east-1"
}

variable "redshift_master_username" {
  type        = string
  description = "Master username for the Redshift cluster."
  default     = "adminuser"
}

variable "redshift_master_password" {
  type        = string
  description = "Master password for the Redshift cluster."
  default     = "ChangeMe12345!"
  sensitive   = true
}

variable "authorized_aws_account_id" {
  type        = string
  description = "AWS account ID to authorize for Redshift endpoint access."
  default     = "012345678910"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "redshift_vpc" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "redshift-endpoint-auth-vpc"
  }
}

resource "aws_internet_gateway" "redshift_igw" {
  vpc_id = aws_vpc.redshift_vpc.id

  tags = {
    Name = "redshift-endpoint-auth-igw"
  }
}

resource "aws_subnet" "redshift_subnet_a" {
  vpc_id                  = aws_vpc.redshift_vpc.id
  cidr_block              = "10.50.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "redshift-subnet-a"
  }
}

resource "aws_subnet" "redshift_subnet_b" {
  vpc_id                  = aws_vpc.redshift_vpc.id
  cidr_block              = "10.50.2.0/24"
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
  name        = "redshift-cluster-sg"
  description = "Security group for the Redshift cluster"
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
    Name = "redshift-cluster-sg"
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

  tags = {
    Name = "redshift-cluster-service-role"
  }
}

resource "aws_iam_role_policy_attachment" "redshift_s3_readonly" {
  role       = aws_iam_role.redshift_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_redshift_subnet_group" "redshift_subnet_group" {
  name        = "redshift-cluster-subnet-group"
  description = "Subnet group for the 2-node Redshift cluster"

  subnet_ids = [
    aws_subnet.redshift_subnet_a.id,
    aws_subnet.redshift_subnet_b.id
  ]

  tags = {
    Name = "redshift-cluster-subnet-group"
  }
}

resource "aws_redshift_cluster" "redshift_cluster" {
  cluster_identifier = "two-node-redshift-cluster"

  database_name   = "dev"
  master_username = var.redshift_master_username
  master_password = var.redshift_master_password

  node_type       = "ra3.xlplus"
  cluster_type    = "multi-node"
  number_of_nodes = 2

  port                          = 5439
  encrypted                     = true
  publicly_accessible           = false
  enhanced_vpc_routing          = true
  skip_final_snapshot           = true
  automated_snapshot_retention_period = 1

  cluster_subnet_group_name = aws_redshift_subnet_group.redshift_subnet_group.name
  vpc_security_group_ids    = [aws_security_group.redshift_sg.id]

  iam_roles = [
    aws_iam_role.redshift_role.arn
  ]

  depends_on = [
    aws_iam_role_policy_attachment.redshift_s3_readonly
  ]

  tags = {
    Name = "two-node-redshift-cluster"
  }
}

resource "aws_redshift_endpoint_authorization" "authorized_account" {
  cluster_identifier = aws_redshift_cluster.redshift_cluster.cluster_identifier
  account            = var.authorized_aws_account_id

  depends_on = [
    aws_redshift_cluster.redshift_cluster
  ]
}

output "redshift_cluster_identifier" {
  description = "Identifier of the Redshift cluster."
  value       = aws_redshift_cluster.redshift_cluster.cluster_identifier
}

output "redshift_cluster_endpoint" {
  description = "Endpoint address of the Redshift cluster."
  value       = aws_redshift_cluster.redshift_cluster.endpoint
}

output "authorized_aws_account_id" {
  description = "AWS account authorized for Redshift endpoint access."
  value       = aws_redshift_endpoint_authorization.authorized_account.account
}
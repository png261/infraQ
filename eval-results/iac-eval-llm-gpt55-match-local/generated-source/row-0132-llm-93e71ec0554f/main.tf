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
  description = "AWS region where resources will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "memcached-demo"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.50.0.0/16"
}

variable "memcached_node_type" {
  description = "Instance class for the Memcached nodes."
  type        = string
  default     = "cache.t3.micro"
}

variable "memcached_node_count" {
  description = "Number of Memcached cache nodes."
  type        = number
  default     = 2
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to access Memcached on port 11211."
  type        = list(string)
  default     = ["10.50.0.0/16"]
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  common_tags = {
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Environment = "demo"
  }

  subnet_cidrs = [
    "10.50.1.0/24",
    "10.50.2.0/24"
  ]
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

resource "aws_subnet" "cache" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-cache-subnet-${count.index + 1}"
  })
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-route-table"
  })
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.main.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "cache" {
  count = length(aws_subnet.cache)

  subnet_id      = aws_subnet.cache[count.index].id
  route_table_id = aws_route_table.main.id
}

resource "aws_security_group" "memcached" {
  name        = "${var.project_name}-memcached-sg"
  description = "Security group for Memcached cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow Memcached access"
    from_port   = 11211
    to_port     = 11211
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-memcached-sg"
  })
}

resource "aws_elasticache_subnet_group" "memcached" {
  name        = "${var.project_name}-subnet-group"
  description = "Subnet group for Memcached cluster"
  subnet_ids  = aws_subnet.cache[*].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-memcached-subnet-group"
  })
}

resource "aws_elasticache_parameter_group" "memcached" {
  name        = "${var.project_name}-memcached-parameter-group"
  family      = "memcached1.6"
  description = "Parameter group for Memcached 1.6"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-memcached-parameter-group"
  })
}

resource "aws_elasticache_cluster" "memcached" {
  cluster_id           = "${var.project_name}-cluster"
  engine               = "memcached"
  engine_version       = "1.6.22"
  node_type            = var.memcached_node_type
  num_cache_nodes      = var.memcached_node_count
  parameter_group_name = aws_elasticache_parameter_group.memcached.name
  subnet_group_name    = aws_elasticache_subnet_group.memcached.name
  security_group_ids   = [aws_security_group.memcached.id]
  port                 = 11211

  az_mode = var.memcached_node_count > 1 ? "cross-az" : "single-az"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-memcached-cluster"
  })
}

output "memcached_cluster_id" {
  description = "ID of the Memcached cluster."
  value       = aws_elasticache_cluster.memcached.cluster_id
}

output "memcached_configuration_endpoint" {
  description = "Configuration endpoint for the Memcached cluster."
  value       = aws_elasticache_cluster.memcached.configuration_endpoint
}

output "memcached_port" {
  description = "Port used by the Memcached cluster."
  value       = aws_elasticache_cluster.memcached.port
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "memcached_security_group_id" {
  description = "Security group ID attached to the Memcached cluster."
  value       = aws_security_group.memcached.id
}
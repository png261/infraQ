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

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "private_subnet_a_cidr" {
  description = "CIDR block for the first private subnet."
  type        = string
  default     = "10.20.1.0/24"
}

variable "private_subnet_b_cidr" {
  description = "CIDR block for the second private subnet."
  type        = string
  default     = "10.20.2.0/24"
}

variable "redis_node_type" {
  description = "Instance class for the Redis cache node."
  type        = string
  default     = "cache.t3.micro"
}

variable "redis_port" {
  description = "Redis port."
  type        = number
  default     = 6379
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "cache_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "database-cache-vpc"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.cache_vpc.id
  cidr_block              = var.private_subnet_a_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "database-cache-private-subnet-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.cache_vpc.id
  cidr_block              = var.private_subnet_b_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "database-cache-private-subnet-b"
  }
}

resource "aws_security_group" "redis" {
  name        = "redis-cache-security-group"
  description = "Allow Redis access from within the VPC"
  vpc_id      = aws_vpc.cache_vpc.id

  ingress {
    description = "Allow Redis traffic from VPC"
    from_port   = var.redis_port
    to_port     = var.redis_port
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.cache_vpc.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "redis-cache-security-group"
  }
}

resource "aws_elasticache_subnet_group" "redis" {
  name        = "database-cache-subnet-group"
  description = "Subnet group for Redis cache"
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  tags = {
    Name = "database-cache-subnet-group"
  }
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "database-call-reduction-cache"
  description          = "Redis cache used to reduce database calls"

  engine         = "redis"
  engine_version = "7.0"
  node_type      = var.redis_node_type
  port           = var.redis_port

  num_cache_clusters = 1

  automatic_failover_enabled = false
  multi_az_enabled           = false

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]

  at_rest_encryption_enabled = true
  transit_encryption_enabled = false

  apply_immediately = true

  tags = {
    Name        = "database-call-reduction-cache"
    Purpose     = "Reduce database calls"
    Environment = "dev"
  }
}

output "redis_primary_endpoint" {
  description = "Primary Redis endpoint for application cache connections."
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_port" {
  description = "Redis port."
  value       = var.redis_port
}

output "vpc_id" {
  description = "VPC ID where the cache was deployed."
  value       = aws_vpc.cache_vpc.id
}
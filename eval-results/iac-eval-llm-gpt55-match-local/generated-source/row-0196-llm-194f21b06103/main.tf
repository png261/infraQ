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
  description = "AWS region where ElastiCache will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "replication_group_id" {
  description = "ID of the ElastiCache replication group."
  type        = string
  default     = "password-auth-redis"
}

variable "elasticache_user_id" {
  description = "ElastiCache ACL user ID."
  type        = string
  default     = "app-user"
}

variable "elasticache_user_name" {
  description = "ElastiCache ACL username used by clients."
  type        = string
  default     = "appuser"
}

variable "node_type" {
  description = "ElastiCache Redis node type."
  type        = string
  default     = "cache.t4g.micro"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "random_password" "redis_password_primary" {
  length           = 32
  special          = true
  override_special = "!&#$^<>-"
}

resource "random_password" "redis_password_secondary" {
  length           = 32
  special          = true
  override_special = "!&#$^<>-"
}

resource "aws_security_group" "elasticache" {
  name        = "${var.replication_group_id}-sg"
  description = "Security group for password-authenticated ElastiCache Redis"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow Redis access from within the default VPC"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_elasticache_subnet_group" "redis" {
  name       = "${var.replication_group_id}-subnet-group"
  subnet_ids = data.aws_subnets.default.ids
}

resource "aws_elasticache_user" "default_disabled" {
  user_id       = "default-disabled-user"
  user_name     = "default"
  engine        = "REDIS"
  access_string = "off ~* +@all"

  authentication_mode {
    type = "no-password-required"
  }
}

resource "aws_elasticache_user" "app_user" {
  user_id       = var.elasticache_user_id
  user_name     = var.elasticache_user_name
  engine        = "REDIS"
  access_string = "on ~* +@all"

  authentication_mode {
    type = "password"
    passwords = [
      random_password.redis_password_primary.result,
      random_password.redis_password_secondary.result
    ]
  }
}

resource "aws_elasticache_user_group" "redis" {
  engine        = "REDIS"
  user_group_id = "${var.replication_group_id}-user-group"

  user_ids = [
    aws_elasticache_user.default_disabled.user_id,
    aws_elasticache_user.app_user.user_id
  ]
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = var.replication_group_id
  description          = "Redis replication group with password-authenticated ACL user"

  engine         = "redis"
  engine_version = "7.0"
  node_type      = var.node_type
  port           = 6379

  num_cache_clusters = 1

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.elasticache.id]

  transit_encryption_enabled = true
  at_rest_encryption_enabled = true

  user_group_ids = [
    aws_elasticache_user_group.redis.user_group_id
  ]

  apply_immediately = true

  depends_on = [
    aws_elasticache_user_group.redis
  ]
}

output "redis_primary_endpoint" {
  description = "Primary endpoint address for the Redis replication group."
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_port" {
  description = "Redis port."
  value       = aws_elasticache_replication_group.redis.port
}

output "redis_username" {
  description = "Password-authenticated ElastiCache username."
  value       = aws_elasticache_user.app_user.user_name
}

output "redis_primary_password" {
  description = "Primary generated Redis password for the application user."
  value       = random_password.redis_password_primary.result
  sensitive   = true
}

output "redis_secondary_password" {
  description = "Secondary generated Redis password for the application user."
  value       = random_password.redis_password_secondary.result
  sensitive   = true
}
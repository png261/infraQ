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

provider "random" {}

variable "aws_region" {
  description = "AWS region where the ElastiCache Redis cluster will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "redis_user_name" {
  description = "Redis ACL username used for authentication."
  type        = string
  default     = "appuser"
}

variable "redis_replication_group_id" {
  description = "Name of the ElastiCache Redis replication group."
  type        = string
  default     = "authenticated-redis"
}

variable "redis_node_type" {
  description = "ElastiCache Redis node instance type."
  type        = string
  default     = "cache.t4g.micro"
}

variable "redis_engine_version" {
  description = "Redis engine version."
  type        = string
  default     = "7.0"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default_vpc_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "random_password" "redis_user_password" {
  length           = 32
  special          = true
  override_special = "!&#$^<>-"
}

resource "aws_security_group" "redis" {
  name        = "${var.redis_replication_group_id}-sg"
  description = "Allow Redis access from within the default VPC"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Redis TLS access from VPC"
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

  tags = {
    Name = "${var.redis_replication_group_id}-sg"
  }
}

resource "aws_elasticache_subnet_group" "redis" {
  name        = "${var.redis_replication_group_id}-subnet-group"
  description = "Subnet group for authenticated Redis ElastiCache cluster"
  subnet_ids  = data.aws_subnets.default_vpc_subnets.ids
}

resource "aws_elasticache_user" "default" {
  user_id       = "${var.redis_replication_group_id}-default-user"
  user_name     = "default"
  engine        = "REDIS"
  access_string = "off ~* &* +@all"

  authentication_mode {
    type = "no-password-required"
  }
}

resource "aws_elasticache_user" "app" {
  user_id       = "${var.redis_replication_group_id}-app-user"
  user_name     = var.redis_user_name
  engine        = "REDIS"
  access_string = "on ~* &* +@all"

  authentication_mode {
    type      = "password"
    passwords = [random_password.redis_user_password.result]
  }
}

resource "aws_elasticache_user_group" "redis" {
  engine        = "REDIS"
  user_group_id = "${var.redis_replication_group_id}-user-group"

  user_ids = [
    aws_elasticache_user.default.user_id,
    aws_elasticache_user.app.user_id
  ]
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = var.redis_replication_group_id
  description          = "Redis replication group using ACL user authentication"

  engine         = "redis"
  engine_version = var.redis_engine_version
  node_type      = var.redis_node_type
  port           = 6379

  num_cache_clusters = 1

  subnet_group_name  = aws_elasticache_subnet_group.redis.name
  security_group_ids = [aws_security_group.redis.id]

  transit_encryption_enabled = true
  at_rest_encryption_enabled = true

  automatic_failover_enabled = false
  multi_az_enabled           = false

  user_group_ids = [
    aws_elasticache_user_group.redis.user_group_id
  ]

  apply_immediately = true

  tags = {
    Name = var.redis_replication_group_id
  }

  depends_on = [
    aws_elasticache_user_group.redis
  ]
}

output "redis_primary_endpoint" {
  description = "Primary endpoint address for the authenticated Redis cluster."
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_port" {
  description = "Redis port."
  value       = aws_elasticache_replication_group.redis.port
}

output "redis_username" {
  description = "Redis ACL username."
  value       = aws_elasticache_user.app.user_name
}

output "redis_password" {
  description = "Redis ACL password. Use this password with the Redis username to authenticate."
  value       = random_password.redis_user_password.result
  sensitive   = true
}

output "redis_tls_connection_example" {
  description = "Example Redis CLI command using TLS and ACL authentication."
  value       = "redis-cli --tls -h ${aws_elasticache_replication_group.redis.primary_endpoint_address} -p 6379 --user ${aws_elasticache_user.app.user_name} -a '<redis_password_output>'"
}
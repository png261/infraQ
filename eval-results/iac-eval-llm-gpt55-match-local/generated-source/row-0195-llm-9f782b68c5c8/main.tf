terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "random" {}

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix used for all resource names."
  type        = string
  default     = "iam-elasticache-demo"
}

variable "elasticache_node_type" {
  description = "ElastiCache Redis node type."
  type        = string
  default     = "cache.t4g.micro"
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  elasticache_user_name = "${var.name_prefix}-iam-user"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.name_prefix}-vpc"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.40.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${var.name_prefix}-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.40.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${var.name_prefix}-private-b"
  }
}

resource "aws_security_group" "elasticache" {
  name        = "${var.name_prefix}-elasticache-sg"
  description = "Security group for IAM-authenticated ElastiCache Redis"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow Redis TLS traffic from inside the VPC"
    from_port   = 6379
    to_port     = 6379
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name_prefix}-elasticache-sg"
  }
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "${var.name_prefix}-subnet-group"
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  tags = {
    Name = "${var.name_prefix}-subnet-group"
  }
}

resource "random_password" "default_user_password" {
  length           = 32
  special          = true
  override_special = "!&#$^<>-"
}

resource "aws_elasticache_user" "default" {
  user_id       = "${var.name_prefix}-default"
  user_name     = "default"
  engine        = "REDIS"
  access_string = "off ~* &* +@all"

  authentication_mode {
    type      = "password"
    passwords = [random_password.default_user_password.result]
  }

  tags = {
    Name = "${var.name_prefix}-default-user"
  }
}

resource "aws_elasticache_user" "iam_user" {
  user_id       = local.elasticache_user_name
  user_name     = local.elasticache_user_name
  engine        = "REDIS"
  access_string = "on ~* &* +@all"

  authentication_mode {
    type = "iam"
  }

  tags = {
    Name = local.elasticache_user_name
  }
}

resource "aws_elasticache_user_group" "main" {
  user_group_id = "${var.name_prefix}-user-group"
  engine        = "REDIS"

  user_ids = [
    aws_elasticache_user.default.user_id,
    aws_elasticache_user.iam_user.user_id
  ]

  tags = {
    Name = "${var.name_prefix}-user-group"
  }
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id = "${var.name_prefix}-redis"
  description          = "Redis replication group with IAM authentication enabled"

  engine         = "redis"
  engine_version = "7.0"
  node_type      = var.elasticache_node_type

  port               = 6379
  num_cache_clusters = 1

  automatic_failover_enabled = false
  multi_az_enabled           = false

  subnet_group_name  = aws_elasticache_subnet_group.main.name
  security_group_ids = [aws_security_group.elasticache.id]

  transit_encryption_enabled = true
  at_rest_encryption_enabled = true

  user_group_ids = [
    aws_elasticache_user_group.main.user_group_id
  ]

  apply_immediately = true

  tags = {
    Name = "${var.name_prefix}-redis"
  }
}

resource "aws_iam_role" "elasticache_client" {
  name = "${var.name_prefix}-elasticache-client-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.name_prefix}-elasticache-client-role"
  }
}

resource "aws_iam_policy" "elasticache_iam_auth" {
  name        = "${var.name_prefix}-elasticache-iam-auth-policy"
  description = "Allows IAM authentication to the ElastiCache Redis user"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowElasticacheIamConnect"
        Effect = "Allow"
        Action = [
          "elasticache:Connect"
        ]
        Resource = [
          "arn:aws:elasticache:${var.aws_region}:${data.aws_caller_identity.current.account_id}:replicationgroup:${aws_elasticache_replication_group.redis.replication_group_id}",
          "arn:aws:elasticache:${var.aws_region}:${data.aws_caller_identity.current.account_id}:user:${aws_elasticache_user.iam_user.user_id}"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "elasticache_iam_auth" {
  role       = aws_iam_role.elasticache_client.name
  policy_arn = aws_iam_policy.elasticache_iam_auth.arn
}

resource "aws_iam_instance_profile" "elasticache_client" {
  name = "${var.name_prefix}-elasticache-client-instance-profile"
  role = aws_iam_role.elasticache_client.name
}

output "redis_primary_endpoint" {
  description = "Primary Redis endpoint. Clients must connect over TLS and use an IAM-generated auth token."
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "redis_port" {
  description = "Redis TLS port."
  value       = aws_elasticache_replication_group.redis.port
}

output "elasticache_iam_user_name" {
  description = "ElastiCache Redis IAM user name. This must be used as the Redis username."
  value       = aws_elasticache_user.iam_user.user_name
}

output "elasticache_client_role_arn" {
  description = "IAM role ARN allowed to authenticate to ElastiCache using IAM."
  value       = aws_iam_role.elasticache_client.arn
}

output "elasticache_client_instance_profile_name" {
  description = "Instance profile that can be attached to EC2 clients needing IAM-authenticated Redis access."
  value       = aws_iam_instance_profile.elasticache_client.name
}
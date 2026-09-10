terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
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

variable "elasticache_user_id" {
  description = "The ElastiCache Redis IAM user ID. For IAM authentication, user_id and user_name must match."
  type        = string
  default     = "iam-redis-user"
}

variable "elasticache_access_string" {
  description = "Redis ACL access string for the ElastiCache user."
  type        = string
  default     = "on ~* +@all"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_elasticache_user" "iam_user" {
  user_id       = var.elasticache_user_id
  user_name     = var.elasticache_user_id
  engine        = "REDIS"
  access_string = var.elasticache_access_string

  authentication_mode {
    type = "iam"
  }

  tags = {
    Name        = var.elasticache_user_id
    ManagedBy   = "Terraform"
    AuthType    = "IAM"
    Environment = "example"
  }
}

data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    sid    = "AllowEC2AssumeRole"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "elasticache_iam_connect_role" {
  name               = "elasticache-iam-connect-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json

  tags = {
    Name      = "elasticache-iam-connect-role"
    ManagedBy = "Terraform"
  }
}

data "aws_iam_policy_document" "elasticache_iam_connect" {
  statement {
    sid    = "AllowElastiCacheIAMConnect"
    effect = "Allow"

    actions = [
      "elasticache:Connect"
    ]

    resources = [
      aws_elasticache_user.iam_user.arn,
      "arn:aws:elasticache:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:replicationgroup:*",
      "arn:aws:elasticache:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:serverlesscache:*"
    ]
  }
}

resource "aws_iam_policy" "elasticache_iam_connect" {
  name        = "elasticache-iam-connect-policy"
  description = "Allows IAM authentication connections to ElastiCache Redis using the configured IAM user."
  policy      = data.aws_iam_policy_document.elasticache_iam_connect.json

  tags = {
    Name      = "elasticache-iam-connect-policy"
    ManagedBy = "Terraform"
  }
}

resource "aws_iam_role_policy_attachment" "elasticache_iam_connect" {
  role       = aws_iam_role.elasticache_iam_connect_role.name
  policy_arn = aws_iam_policy.elasticache_iam_connect.arn
}

resource "aws_iam_instance_profile" "elasticache_iam_connect" {
  name = "elasticache-iam-connect-instance-profile"
  role = aws_iam_role.elasticache_iam_connect_role.name

  tags = {
    Name      = "elasticache-iam-connect-instance-profile"
    ManagedBy = "Terraform"
  }
}

output "elasticache_user_id" {
  description = "The ID of the IAM-enabled ElastiCache user."
  value       = aws_elasticache_user.iam_user.user_id
}

output "elasticache_user_arn" {
  description = "The ARN of the IAM-enabled ElastiCache user."
  value       = aws_elasticache_user.iam_user.arn
}

output "iam_role_name" {
  description = "IAM role name that can be used by EC2 instances to connect to ElastiCache with IAM authentication."
  value       = aws_iam_role.elasticache_iam_connect_role.name
}

output "iam_instance_profile_name" {
  description = "Instance profile that can be attached to EC2 instances for ElastiCache IAM authentication."
  value       = aws_iam_instance_profile.elasticache_iam_connect.name
}
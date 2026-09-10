terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
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

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "redshift-events-demo"
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

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

resource "random_password" "redshift_master_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "redshift_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.50.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-subnet-a"
  }
}

resource "aws_subnet" "redshift_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.50.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-subnet-b"
  }
}

resource "aws_redshift_subnet_group" "main" {
  name       = "${var.project_name}-subnet-group"
  subnet_ids = [
    aws_subnet.redshift_a.id,
    aws_subnet.redshift_b.id
  ]

  tags = {
    Name = "${var.project_name}-subnet-group"
  }
}

resource "aws_security_group" "redshift" {
  name        = "${var.project_name}-redshift-sg"
  description = "Security group for Redshift cluster"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-redshift-sg"
  }
}

resource "aws_redshift_cluster" "main" {
  cluster_identifier = "${var.project_name}-cluster"

  database_name   = var.redshift_database_name
  master_username = var.redshift_master_username
  master_password = random_password.redshift_master_password.result

  node_type    = "dc2.large"
  cluster_type = "single-node"

  cluster_subnet_group_name = aws_redshift_subnet_group.main.name
  vpc_security_group_ids    = [aws_security_group.redshift.id]

  publicly_accessible                = false
  encrypted                          = true
  enhanced_vpc_routing               = false
  automated_snapshot_retention_period = 1
  skip_final_snapshot                = true

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

resource "aws_sns_topic" "redshift_events" {
  name = "${var.project_name}-redshift-events"

  tags = {
    Name = "${var.project_name}-redshift-events"
  }
}

resource "aws_sns_topic_policy" "allow_redshift_publish" {
  arn = aws_sns_topic.redshift_events.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowRedshiftToPublishEvents"
        Effect = "Allow"
        Principal = {
          Service = "redshift.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.redshift_events.arn
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_redshift_event_subscription" "cluster_events" {
  name          = "${var.project_name}-event-subscription"
  sns_topic_arn = aws_sns_topic.redshift_events.arn

  source_type = "cluster"
  source_ids  = [aws_redshift_cluster.main.cluster_identifier]

  enabled = true

  depends_on = [
    aws_redshift_cluster.main,
    aws_sns_topic_policy.allow_redshift_publish
  ]

  tags = {
    Name = "${var.project_name}-event-subscription"
  }
}

output "redshift_cluster_identifier" {
  description = "Identifier of the created Redshift cluster."
  value       = aws_redshift_cluster.main.cluster_identifier
}

output "redshift_cluster_endpoint" {
  description = "Endpoint address of the Redshift cluster."
  value       = aws_redshift_cluster.main.endpoint
}

output "redshift_master_username" {
  description = "Master username for the Redshift cluster."
  value       = var.redshift_master_username
}

output "redshift_master_password" {
  description = "Generated master password for the Redshift cluster."
  value       = random_password.redshift_master_password.result
  sensitive   = true
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic receiving Redshift events."
  value       = aws_sns_topic.redshift_events.arn
}

output "redshift_event_subscription_name" {
  description = "Name of the Redshift event subscription."
  value       = aws_redshift_event_subscription.cluster_events.name
}
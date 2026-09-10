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
  description = "AWS region where the Redshift cluster will be created."
  type        = string
  default     = "us-east-1"
}

variable "cluster_identifier" {
  description = "Identifier for the Redshift cluster."
  type        = string
  default     = "example-redshift-cluster"
}

variable "database_name" {
  description = "Initial database name for the Redshift cluster."
  type        = string
  default     = "dev"
}

variable "master_username" {
  description = "Master username for the Redshift cluster."
  type        = string
  default     = "adminuser"
}

variable "redshift_node_type" {
  description = "Node type for the Redshift cluster."
  type        = string
  default     = "dc2.large"
}

variable "redshift_port" {
  description = "Port for Redshift connections."
  type        = number
  default     = 5439
}

variable "event_subscription_name" {
  description = "Name of the Redshift event subscription."
  type        = string
  default     = "example-redshift-event-subscription"
}

data "aws_caller_identity" "current" {}

data "aws_default_vpc" "default" {}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_default_vpc.default.id]
  }
}

resource "random_password" "redshift_master_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_security_group" "redshift" {
  name        = "${var.cluster_identifier}-sg"
  description = "Security group for Redshift cluster"
  vpc_id      = data.aws_default_vpc.default.id

  ingress {
    description = "Allow Redshift access from within the default VPC"
    from_port   = var.redshift_port
    to_port     = var.redshift_port
    protocol    = "tcp"
    cidr_blocks = [data.aws_default_vpc.default.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_identifier}-sg"
  }
}

resource "aws_redshift_subnet_group" "redshift" {
  name        = "${var.cluster_identifier}-subnet-group"
  description = "Subnet group for Redshift cluster"
  subnet_ids  = data.aws_subnets.default.ids

  tags = {
    Name = "${var.cluster_identifier}-subnet-group"
  }
}

resource "aws_sns_topic" "redshift_events" {
  name = "${var.cluster_identifier}-events"

  tags = {
    Name = "${var.cluster_identifier}-events"
  }
}

data "aws_iam_policy_document" "sns_topic_policy" {
  statement {
    sid    = "AllowRedshiftToPublishEvents"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["redshift.amazonaws.com"]
    }

    actions = [
      "SNS:Publish"
    ]

    resources = [
      aws_sns_topic.redshift_events.arn
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "redshift_events" {
  arn    = aws_sns_topic.redshift_events.arn
  policy = data.aws_iam_policy_document.sns_topic_policy.json
}

resource "aws_redshift_cluster" "main" {
  cluster_identifier = var.cluster_identifier
  database_name      = var.database_name
  master_username    = var.master_username
  master_password    = random_password.redshift_master_password.result

  node_type    = var.redshift_node_type
  cluster_type = "single-node"

  port                              = var.redshift_port
  publicly_accessible               = false
  encrypted                         = true
  enhanced_vpc_routing              = true
  allow_version_upgrade             = true
  automated_snapshot_retention_period = 1

  vpc_security_group_ids    = [aws_security_group.redshift.id]
  cluster_subnet_group_name = aws_redshift_subnet_group.redshift.name

  skip_final_snapshot = true

  tags = {
    Name = var.cluster_identifier
  }
}

resource "aws_redshift_event_subscription" "cluster_events" {
  name          = var.event_subscription_name
  sns_topic_arn = aws_sns_topic.redshift_events.arn

  source_type = "cluster"
  source_ids  = [aws_redshift_cluster.main.cluster_identifier]

  severity = "INFO"

  event_categories = [
    "configuration",
    "management",
    "monitoring",
    "security",
    "pending"
  ]

  enabled = true

  depends_on = [
    aws_sns_topic_policy.redshift_events,
    aws_redshift_cluster.main
  ]

  tags = {
    Name = var.event_subscription_name
  }
}

output "redshift_cluster_identifier" {
  description = "The Redshift cluster identifier."
  value       = aws_redshift_cluster.main.cluster_identifier
}

output "redshift_cluster_endpoint" {
  description = "The Redshift cluster endpoint."
  value       = aws_redshift_cluster.main.endpoint
}

output "redshift_database_name" {
  description = "The initial Redshift database name."
  value       = aws_redshift_cluster.main.database_name
}

output "redshift_master_username" {
  description = "The Redshift master username."
  value       = aws_redshift_cluster.main.master_username
}

output "redshift_master_password" {
  description = "The generated Redshift master password."
  value       = random_password.redshift_master_password.result
  sensitive   = true
}

output "sns_topic_arn" {
  description = "SNS topic ARN used for Redshift event notifications."
  value       = aws_sns_topic.redshift_events.arn
}

output "redshift_event_subscription_name" {
  description = "Name of the Redshift event subscription."
  value       = aws_redshift_event_subscription.cluster_events.name
}
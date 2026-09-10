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
  description = "AWS region where the Redshift cluster will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "redshift_cluster_identifier" {
  description = "Identifier for the Redshift cluster."
  type        = string
  default     = "example-redshift-cluster"
}

variable "redshift_database_name" {
  description = "Initial database name for the Redshift cluster."
  type        = string
  default     = "exampledb"
}

variable "redshift_master_username" {
  description = "Master username for the Redshift cluster."
  type        = string
  default     = "adminuser"
}

variable "redshift_master_password" {
  description = "Master password for the Redshift cluster."
  type        = string
  sensitive   = true
  default     = "ExamplePassword123!"
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "example-redshift"
}

resource "aws_vpc" "redshift" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_subnet" "redshift_a" {
  vpc_id                  = aws_vpc.redshift.id
  cidr_block              = "10.40.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-subnet-a"
  }
}

resource "aws_subnet" "redshift_b" {
  vpc_id                  = aws_vpc.redshift.id
  cidr_block              = "10.40.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-subnet-b"
  }
}

resource "aws_route_table" "redshift" {
  vpc_id = aws_vpc.redshift.id

  tags = {
    Name = "${local.name_prefix}-route-table"
  }
}

resource "aws_route_table_association" "redshift_a" {
  subnet_id      = aws_subnet.redshift_a.id
  route_table_id = aws_route_table.redshift.id
}

resource "aws_route_table_association" "redshift_b" {
  subnet_id      = aws_subnet.redshift_b.id
  route_table_id = aws_route_table.redshift.id
}

resource "aws_security_group" "redshift" {
  name        = "${local.name_prefix}-sg"
  description = "Security group for the example Redshift cluster"
  vpc_id      = aws_vpc.redshift.id

  ingress {
    description = "Allow Redshift access from within the VPC"
    from_port   = 5439
    to_port     = 5439
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.redshift.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sg"
  }
}

resource "aws_redshift_subnet_group" "example" {
  name        = "${local.name_prefix}-subnet-group"
  description = "Subnet group for the example Redshift cluster"

  subnet_ids = [
    aws_subnet.redshift_a.id,
    aws_subnet.redshift_b.id
  ]

  tags = {
    Name = "${local.name_prefix}-subnet-group"
  }
}

resource "aws_redshift_parameter_group" "example" {
  name        = "${local.name_prefix}-parameter-group"
  family      = "redshift-1.0"
  description = "Example Redshift parameter group with custom parameters"

  parameter {
    name  = "require_ssl"
    value = "true"
  }

  parameter {
    name  = "enable_user_activity_logging"
    value = "true"
  }

  parameter {
    name  = "max_concurrency_scaling_clusters"
    value = "1"
  }

  parameter {
    name = "wlm_json_configuration"
    value = jsonencode([
      {
        query_group = []
        user_group  = []
        query_concurrency = 5
        memory_percent_to_use = 100
      }
    ])
  }

  tags = {
    Name = "${local.name_prefix}-parameter-group"
  }
}

resource "aws_iam_role" "redshift" {
  name = "${local.name_prefix}-role"

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
    Name = "${local.name_prefix}-role"
  }
}

resource "aws_iam_role_policy_attachment" "redshift_s3_read_only" {
  role       = aws_iam_role.redshift.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_sns_topic" "redshift_events" {
  name = "${local.name_prefix}-parameter-group-events"

  tags = {
    Name = "${local.name_prefix}-parameter-group-events"
  }
}

resource "aws_sns_topic_policy" "redshift_events" {
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
        Action   = "sns:Publish"
        Resource = aws_sns_topic.redshift_events.arn
        Condition = {
          StringEquals = {
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_redshift_cluster" "example" {
  cluster_identifier = var.redshift_cluster_identifier
  database_name      = var.redshift_database_name

  master_username = var.redshift_master_username
  master_password = var.redshift_master_password

  node_type    = "ra3.xlplus"
  cluster_type = "single-node"

  cluster_subnet_group_name = aws_redshift_subnet_group.example.name
  vpc_security_group_ids    = [aws_security_group.redshift.id]

  cluster_parameter_group_name = aws_redshift_parameter_group.example.name

  iam_roles = [
    aws_iam_role.redshift.arn
  ]

  encrypted           = true
  publicly_accessible = false

  automated_snapshot_retention_period = 1
  preferred_maintenance_window        = "sun:05:00-sun:06:00"

  skip_final_snapshot = true

  depends_on = [
    aws_iam_role_policy_attachment.redshift_s3_read_only
  ]

  tags = {
    Name = var.redshift_cluster_identifier
  }
}

resource "aws_redshift_event_subscription" "parameter_group_events" {
  name          = "${local.name_prefix}-parameter-group-event-subscription"
  sns_topic_arn = aws_sns_topic.redshift_events.arn

  source_type = "cluster-parameter-group"
  source_ids  = [aws_redshift_parameter_group.example.name]

  event_categories = [
    "configuration"
  ]

  severity = "INFO"
  enabled  = true

  depends_on = [
    aws_sns_topic_policy.redshift_events,
    aws_redshift_parameter_group.example
  ]

  tags = {
    Name = "${local.name_prefix}-parameter-group-event-subscription"
  }
}

output "redshift_cluster_identifier" {
  description = "The Redshift cluster identifier."
  value       = aws_redshift_cluster.example.cluster_identifier
}

output "redshift_cluster_endpoint" {
  description = "The Redshift cluster endpoint."
  value       = aws_redshift_cluster.example.endpoint
}

output "redshift_parameter_group_name" {
  description = "The Redshift parameter group name."
  value       = aws_redshift_parameter_group.example.name
}

output "redshift_event_sns_topic_arn" {
  description = "SNS topic ARN receiving Redshift parameter group event notifications."
  value       = aws_sns_topic.redshift_events.arn
}
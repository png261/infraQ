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
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"
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
  default     = "ChangeMe12345!"
}

resource "aws_vpc" "redshift_vpc" {
  cidr_block           = "10.50.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "example-redshift-vpc"
  }
}

resource "aws_internet_gateway" "redshift_igw" {
  vpc_id = aws_vpc.redshift_vpc.id

  tags = {
    Name = "example-redshift-igw"
  }
}

resource "aws_subnet" "redshift_subnet_a" {
  vpc_id                  = aws_vpc.redshift_vpc.id
  cidr_block              = "10.50.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "example-redshift-subnet-a"
  }
}

resource "aws_subnet" "redshift_subnet_b" {
  vpc_id                  = aws_vpc.redshift_vpc.id
  cidr_block              = "10.50.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "example-redshift-subnet-b"
  }
}

resource "aws_route_table" "redshift_route_table" {
  vpc_id = aws_vpc.redshift_vpc.id

  tags = {
    Name = "example-redshift-route-table"
  }
}

resource "aws_route_table_association" "redshift_subnet_a" {
  subnet_id      = aws_subnet.redshift_subnet_a.id
  route_table_id = aws_route_table.redshift_route_table.id
}

resource "aws_route_table_association" "redshift_subnet_b" {
  subnet_id      = aws_subnet.redshift_subnet_b.id
  route_table_id = aws_route_table.redshift_route_table.id
}

resource "aws_security_group" "redshift_sg" {
  name        = "example-redshift-sg"
  description = "Security group for the example Redshift cluster"
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
    Name = "example-redshift-sg"
  }
}

resource "aws_redshift_subnet_group" "example" {
  name        = "example-redshift-subnet-group"
  description = "Example Redshift subnet group"
  subnet_ids = [
    aws_subnet.redshift_subnet_a.id,
    aws_subnet.redshift_subnet_b.id
  ]

  tags = {
    Name = "example-redshift-subnet-group"
  }
}

resource "aws_redshift_parameter_group" "example" {
  name        = "example-redshift-parameter-group"
  family      = "redshift-1.0"
  description = "Example Redshift parameter group for event subscription"

  parameter {
    name  = "require_ssl"
    value = "true"
  }

  tags = {
    Name = "example-redshift-parameter-group"
  }
}

resource "aws_sns_topic" "redshift_events" {
  name = "example-redshift-parameter-group-events"

  tags = {
    Name = "example-redshift-parameter-group-events"
  }
}

resource "aws_sns_topic_policy" "redshift_events" {
  arn = aws_sns_topic.redshift_events.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "RedshiftPublishPolicy"
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
            "AWS:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      }
    ]
  })
}

resource "aws_redshift_cluster" "example" {
  cluster_identifier = "example-redshift-cluster"

  database_name   = "exampledb"
  master_username = var.redshift_master_username
  master_password = var.redshift_master_password

  node_type    = "dc2.large"
  cluster_type = "single-node"

  port                       = 5439
  publicly_accessible        = false
  encrypted                  = true
  enhanced_vpc_routing       = false
  allow_version_upgrade      = true
  automated_snapshot_retention_period = 1

  cluster_subnet_group_name = aws_redshift_subnet_group.example.name
  vpc_security_group_ids    = [aws_security_group.redshift_sg.id]
  cluster_parameter_group_name = aws_redshift_parameter_group.example.name

  skip_final_snapshot = true

  tags = {
    Name = "example-redshift-cluster"
  }
}

resource "aws_redshift_event_subscription" "parameter_group_events" {
  name          = "example-redshift-parameter-group-event-subscription"
  sns_topic_arn = aws_sns_topic.redshift_events.arn

  source_type = "cluster-parameter-group"
  source_ids  = [aws_redshift_parameter_group.example.name]

  event_categories = [
    "configuration"
  ]

  severity = "INFO"
  enabled  = true

  depends_on = [
    aws_sns_topic_policy.redshift_events
  ]

  tags = {
    Name = "example-redshift-parameter-group-event-subscription"
  }
}

output "redshift_cluster_identifier" {
  description = "The Redshift cluster identifier."
  value       = aws_redshift_cluster.example.cluster_identifier
}

output "redshift_parameter_group_name" {
  description = "The Redshift parameter group name."
  value       = aws_redshift_parameter_group.example.name
}

output "sns_topic_arn" {
  description = "The SNS topic ARN receiving Redshift parameter group events."
  value       = aws_sns_topic.redshift_events.arn
}

output "redshift_event_subscription_name" {
  description = "The Redshift event subscription name."
  value       = aws_redshift_event_subscription.parameter_group_events.name
}
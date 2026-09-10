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
  description = "AWS region where the MSK cluster will be created."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the MSK cluster."
  type        = string
  default     = "managed-msk-cluster"
}

variable "kafka_version" {
  description = "Apache Kafka version for the MSK cluster."
  type        = string
  default     = "3.6.0"
}

variable "broker_instance_type" {
  description = "Instance type for MSK broker nodes."
  type        = string
  default     = "kafka.t3.small"
}

variable "broker_volume_size" {
  description = "EBS volume size in GiB for each broker."
  type        = number
  default     = 100
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "msk_vpc" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "msk-vpc"
  }
}

resource "aws_subnet" "msk_subnet_a" {
  vpc_id                  = aws_vpc.msk_vpc.id
  cidr_block              = "10.40.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "msk-subnet-a"
  }
}

resource "aws_subnet" "msk_subnet_b" {
  vpc_id                  = aws_vpc.msk_vpc.id
  cidr_block              = "10.40.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "msk-subnet-b"
  }
}

resource "aws_security_group" "msk_sg" {
  name        = "msk-security-group"
  description = "Security group for MSK brokers"
  vpc_id      = aws_vpc.msk_vpc.id

  ingress {
    description = "Allow Kafka plaintext traffic from within VPC"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk_vpc.cidr_block]
  }

  ingress {
    description = "Allow Kafka TLS traffic from within VPC"
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk_vpc.cidr_block]
  }

  ingress {
    description = "Allow Kafka IAM-authenticated traffic from within VPC"
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk_vpc.cidr_block]
  }

  ingress {
    description = "Allow Zookeeper plaintext traffic from within VPC"
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk_vpc.cidr_block]
  }

  ingress {
    description = "Allow Zookeeper TLS traffic from within VPC"
    from_port   = 2182
    to_port     = 2182
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk_vpc.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "msk-security-group"
  }
}

resource "aws_cloudwatch_log_group" "msk_logs" {
  name              = "/aws/msk/${var.cluster_name}"
  retention_in_days = 30

  tags = {
    Name = "msk-cloudwatch-log-group"
  }
}

resource "aws_msk_cluster" "managed_msk" {
  cluster_name           = var.cluster_name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = 2

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = [
      aws_subnet.msk_subnet_a.id,
      aws_subnet.msk_subnet_b.id
    ]
    security_groups = [aws_security_group.msk_sg.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.broker_volume_size
      }
    }
  }

  client_authentication {
    unauthenticated = true
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
      in_cluster    = true
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk_logs.name
      }
    }
  }

  enhanced_monitoring = "PER_TOPIC_PER_BROKER"

  tags = {
    Name = var.cluster_name
  }
}

output "msk_cluster_arn" {
  description = "ARN of the MSK cluster."
  value       = aws_msk_cluster.managed_msk.arn
}

output "msk_cluster_name" {
  description = "Name of the MSK cluster."
  value       = aws_msk_cluster.managed_msk.cluster_name
}

output "cloudwatch_log_group_name" {
  description = "CloudWatch Log Group receiving MSK broker logs."
  value       = aws_cloudwatch_log_group.msk_logs.name
}

output "bootstrap_brokers" {
  description = "Plaintext bootstrap brokers for the MSK cluster."
  value       = aws_msk_cluster.managed_msk.bootstrap_brokers
}

output "bootstrap_brokers_tls" {
  description = "TLS bootstrap brokers for the MSK cluster."
  value       = aws_msk_cluster.managed_msk.bootstrap_brokers_tls
}
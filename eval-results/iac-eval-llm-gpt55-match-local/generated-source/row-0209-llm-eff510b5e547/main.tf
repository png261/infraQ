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
  description = "AWS region to deploy the MSK cluster into."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the MSK cluster."
  type        = string
  default     = "three-broker-msk-cluster"
}

variable "vpc_cidr" {
  description = "CIDR block for the MSK VPC."
  type        = string
  default     = "10.50.0.0/16"
}

variable "kafka_version" {
  description = "Kafka version for the MSK cluster."
  type        = string
  default     = "3.6.0"
}

variable "broker_instance_type" {
  description = "Instance type for MSK broker nodes."
  type        = string
  default     = "kafka.t3.small"
}

variable "broker_ebs_volume_size" {
  description = "EBS volume size in GiB for each broker."
  type        = number
  default     = 100
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

resource "aws_vpc" "msk" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

resource "aws_subnet" "private" {
  count = 3

  vpc_id            = aws_vpc.msk.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 1)
  availability_zone = local.azs[count.index]

  tags = {
    Name = "${var.cluster_name}-private-subnet-${count.index + 1}"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.msk.id

  tags = {
    Name = "${var.cluster_name}-private-route-table"
  }
}

resource "aws_route_table_association" "private" {
  count = 3

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "msk" {
  name        = "${var.cluster_name}-sg"
  description = "Security group for the MSK brokers"
  vpc_id      = aws_vpc.msk.id

  ingress {
    description = "Allow Kafka plaintext traffic from within VPC"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk.cidr_block]
  }

  ingress {
    description = "Allow Kafka TLS traffic from within VPC"
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk.cidr_block]
  }

  ingress {
    description = "Allow Kafka IAM authentication traffic from within VPC"
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk.cidr_block]
  }

  ingress {
    description = "Allow ZooKeeper TLS traffic from within VPC"
    from_port   = 2182
    to_port     = 2182
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-sg"
  }
}

resource "aws_msk_cluster" "this" {
  cluster_name           = var.cluster_name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = aws_subnet.private[*].id
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.broker_ebs_volume_size
      }
    }
  }

  client_authentication {
    sasl {
      iam = true
    }

    unauthenticated = true
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
      in_cluster    = true
    }
  }

  enhanced_monitoring = "DEFAULT"

  tags = {
    Name        = var.cluster_name
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

output "msk_cluster_arn" {
  description = "ARN of the MSK cluster."
  value       = aws_msk_cluster.this.arn
}

output "msk_cluster_name" {
  description = "Name of the MSK cluster."
  value       = aws_msk_cluster.this.cluster_name
}

output "bootstrap_brokers" {
  description = "Plaintext bootstrap broker connection string."
  value       = aws_msk_cluster.this.bootstrap_brokers
}

output "bootstrap_brokers_tls" {
  description = "TLS bootstrap broker connection string."
  value       = aws_msk_cluster.this.bootstrap_brokers_tls
}

output "bootstrap_brokers_sasl_iam" {
  description = "IAM SASL bootstrap broker connection string."
  value       = aws_msk_cluster.this.bootstrap_brokers_sasl_iam
}
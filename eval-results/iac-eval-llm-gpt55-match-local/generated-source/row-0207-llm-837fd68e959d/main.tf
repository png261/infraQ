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
  description = "AWS region where the MSK cluster will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the MSK cluster."
  type        = string
  default     = "managed-msk-prometheus-cluster"
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

variable "vpc_cidr" {
  description = "CIDR block for the MSK VPC."
  type        = string
  default     = "10.40.0.0/16"
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az_count = 3

  selected_azs = slice(data.aws_availability_zones.available.names, 0, local.az_count)

  subnet_cidrs = [
    "10.40.1.0/24",
    "10.40.2.0/24",
    "10.40.3.0/24"
  ]
}

resource "aws_vpc" "msk" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.cluster_name}-vpc"
  }
}

resource "aws_internet_gateway" "msk" {
  vpc_id = aws_vpc.msk.id

  tags = {
    Name = "${var.cluster_name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.msk.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.msk.id
  }

  tags = {
    Name = "${var.cluster_name}-public-rt"
  }
}

resource "aws_subnet" "msk" {
  count = local.az_count

  vpc_id                  = aws_vpc.msk.id
  cidr_block              = local.subnet_cidrs[count.index]
  availability_zone       = local.selected_azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.cluster_name}-subnet-${count.index + 1}"
  }
}

resource "aws_route_table_association" "public" {
  count = local.az_count

  subnet_id      = aws_subnet.msk[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "msk" {
  name        = "${var.cluster_name}-sg"
  description = "Security group for MSK brokers with Kafka and Prometheus exporter access"
  vpc_id      = aws_vpc.msk.id

  ingress {
    description = "Kafka plaintext access from within VPC"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Kafka TLS access from within VPC"
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "JMX exporter access from within VPC"
    from_port   = 11001
    to_port     = 11001
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Node exporter access from within VPC"
    from_port   = 11002
    to_port     = 11002
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Allow all traffic between MSK brokers"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
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
    client_subnets  = aws_subnet.msk[*].id
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.broker_ebs_volume_size
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

  enhanced_monitoring = "PER_BROKER"

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }

      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled = false
      }

      firehose {
        enabled = false
      }

      s3 {
        enabled = false
      }
    }
  }

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

output "bootstrap_brokers_plaintext" {
  description = "Plaintext bootstrap broker connection string."
  value       = aws_msk_cluster.this.bootstrap_brokers
}

output "bootstrap_brokers_tls" {
  description = "TLS bootstrap broker connection string."
  value       = aws_msk_cluster.this.bootstrap_brokers_tls
}

output "zookeeper_connect_string" {
  description = "Apache ZooKeeper connection string for the MSK cluster."
  value       = aws_msk_cluster.this.zookeeper_connect_string
}

output "prometheus_jmx_exporter_port" {
  description = "Port used by the MSK JMX exporter."
  value       = 11001
}

output "prometheus_node_exporter_port" {
  description = "Port used by the MSK node exporter."
  value       = 11002
}
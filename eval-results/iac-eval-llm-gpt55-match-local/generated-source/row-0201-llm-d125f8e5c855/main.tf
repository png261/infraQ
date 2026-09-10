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

variable "cluster_name" {
  description = "Name of the MSK cluster."
  type        = string
  default     = "example-managed-msk-cluster"
}

variable "vpc_cidr" {
  description = "CIDR block for the MSK VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "broker_instance_type" {
  description = "Instance type for MSK broker nodes."
  type        = string
  default     = "kafka.m5.large"
}

variable "kafka_version" {
  description = "Kafka version for the MSK cluster."
  type        = string
  default     = "3.5.1"
}

variable "broker_ebs_volume_size" {
  description = "EBS volume size in GiB for each broker."
  type        = number
  default     = 100
}

data "aws_availability_zones" "available" {
  state = "available"
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
  count = 3

  vpc_id                  = aws_vpc.msk.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.cluster_name}-subnet-${count.index + 1}"
  }
}

resource "aws_route_table_association" "msk" {
  count = 3

  subnet_id      = aws_subnet.msk[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "msk" {
  name        = "${var.cluster_name}-sg"
  description = "Security group for MSK cluster"
  vpc_id      = aws_vpc.msk.id

  ingress {
    description = "Allow Kafka plaintext traffic within VPC"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk.cidr_block]
  }

  ingress {
    description = "Allow Kafka TLS traffic within VPC"
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk.cidr_block]
  }

  ingress {
    description = "Allow Kafka IAM auth traffic within VPC"
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk.cidr_block]
  }

  ingress {
    description = "Allow Apache ZooKeeper traffic within VPC"
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk.cidr_block]
  }

  ingress {
    description = "Allow Apache ZooKeeper TLS traffic within VPC"
    from_port   = 2182
    to_port     = 2182
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk.cidr_block]
  }

  ingress {
    description = "Allow JMX monitoring within VPC"
    from_port   = 11001
    to_port     = 11001
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk.cidr_block]
  }

  ingress {
    description = "Allow Node Exporter monitoring within VPC"
    from_port   = 11002
    to_port     = 11002
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

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${var.cluster_name}"
  retention_in_days = 14

  tags = {
    Name = "${var.cluster_name}-logs"
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

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }
    }
  }

  tags = {
    Name = var.cluster_name
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

output "zookeeper_connect_string" {
  description = "Apache ZooKeeper connection string for the MSK cluster."
  value       = aws_msk_cluster.this.zookeeper_connect_string
}

output "bootstrap_brokers" {
  description = "Plaintext bootstrap broker connection string."
  value       = aws_msk_cluster.this.bootstrap_brokers
}

output "bootstrap_brokers_tls" {
  description = "TLS bootstrap broker connection string."
  value       = aws_msk_cluster.this.bootstrap_brokers_tls
}
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
  default     = "example-msk-cluster"
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

variable "broker_volume_size" {
  description = "EBS volume size in GiB for each broker."
  type        = number
  default     = 100
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "msk_vpc" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "msk-vpc"
  }
}

resource "aws_internet_gateway" "msk_igw" {
  vpc_id = aws_vpc.msk_vpc.id

  tags = {
    Name = "msk-igw"
  }
}

resource "aws_route_table" "msk_public_rt" {
  vpc_id = aws_vpc.msk_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.msk_igw.id
  }

  tags = {
    Name = "msk-public-route-table"
  }
}

resource "aws_subnet" "msk_subnet_a" {
  vpc_id                  = aws_vpc.msk_vpc.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "msk-subnet-a"
  }
}

resource "aws_subnet" "msk_subnet_b" {
  vpc_id                  = aws_vpc.msk_vpc.id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "msk-subnet-b"
  }
}

resource "aws_subnet" "msk_subnet_c" {
  vpc_id                  = aws_vpc.msk_vpc.id
  cidr_block              = "10.20.3.0/24"
  availability_zone       = data.aws_availability_zones.available.names[2]
  map_public_ip_on_launch = true

  tags = {
    Name = "msk-subnet-c"
  }
}

resource "aws_route_table_association" "msk_subnet_a_assoc" {
  subnet_id      = aws_subnet.msk_subnet_a.id
  route_table_id = aws_route_table.msk_public_rt.id
}

resource "aws_route_table_association" "msk_subnet_b_assoc" {
  subnet_id      = aws_subnet.msk_subnet_b.id
  route_table_id = aws_route_table.msk_public_rt.id
}

resource "aws_route_table_association" "msk_subnet_c_assoc" {
  subnet_id      = aws_subnet.msk_subnet_c.id
  route_table_id = aws_route_table.msk_public_rt.id
}

resource "aws_security_group" "msk_sg" {
  name        = "msk-security-group"
  description = "Security group for MSK cluster"
  vpc_id      = aws_vpc.msk_vpc.id

  ingress {
    description = "Allow plaintext Kafka traffic within VPC"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk_vpc.cidr_block]
  }

  ingress {
    description = "Allow TLS Kafka traffic within VPC"
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk_vpc.cidr_block]
  }

  ingress {
    description = "Allow Kafka broker-to-broker and internal communication"
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk_vpc.cidr_block]
  }

  ingress {
    description = "Allow Zookeeper TLS traffic within VPC"
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
  retention_in_days = 7

  tags = {
    Name = "msk-log-group"
  }
}

resource "aws_msk_configuration" "msk_config" {
  name           = "${var.cluster_name}-configuration"
  kafka_versions = [var.kafka_version]

  server_properties = <<PROPERTIES
auto.create.topics.enable=true
delete.topic.enable=true
log.retention.hours=168
PROPERTIES
}

resource "aws_msk_cluster" "msk_cluster" {
  cluster_name           = var.cluster_name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = [
      aws_subnet.msk_subnet_a.id,
      aws_subnet.msk_subnet_b.id,
      aws_subnet.msk_subnet_c.id
    ]
    security_groups = [aws_security_group.msk_sg.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.broker_volume_size
      }
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.msk_config.arn
    revision = aws_msk_configuration.msk_config.latest_revision
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
      in_cluster    = true
    }
  }

  client_authentication {
    unauthenticated = true
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk_logs.name
      }
    }
  }

  tags = {
    Name        = var.cluster_name
    Environment = "example"
  }
}

output "msk_cluster_arn" {
  description = "ARN of the MSK cluster."
  value       = aws_msk_cluster.msk_cluster.arn
}

output "msk_cluster_name" {
  description = "Name of the MSK cluster."
  value       = aws_msk_cluster.msk_cluster.cluster_name
}

output "msk_bootstrap_brokers" {
  description = "Plaintext bootstrap broker connection string."
  value       = aws_msk_cluster.msk_cluster.bootstrap_brokers
}

output "msk_bootstrap_brokers_tls" {
  description = "TLS bootstrap broker connection string."
  value       = aws_msk_cluster.msk_cluster.bootstrap_brokers_tls
}

output "vpc_id" {
  description = "ID of the VPC created for MSK."
  value       = aws_vpc.msk_vpc.id
}
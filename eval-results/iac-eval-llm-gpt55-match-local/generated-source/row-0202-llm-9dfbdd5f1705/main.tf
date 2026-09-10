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
  region = "us-east-2"
}

variable "cluster_name" {
  description = "Name of the MSK cluster"
  type        = string
  default     = "managed-msk-cluster"
}

variable "kafka_version" {
  description = "Apache Kafka version for the MSK cluster"
  type        = string
  default     = "3.6.0"
}

variable "broker_instance_type" {
  description = "Instance type for MSK broker nodes"
  type        = string
  default     = "kafka.t3.small"
}

variable "broker_ebs_volume_size" {
  description = "EBS storage size in GiB per broker"
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
    Name = "msk-internet-gateway"
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

resource "aws_subnet" "msk_subnet_1" {
  vpc_id                  = aws_vpc.msk_vpc.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "msk-subnet-1"
  }
}

resource "aws_subnet" "msk_subnet_2" {
  vpc_id                  = aws_vpc.msk_vpc.id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "msk-subnet-2"
  }
}

resource "aws_subnet" "msk_subnet_3" {
  vpc_id                  = aws_vpc.msk_vpc.id
  cidr_block              = "10.20.3.0/24"
  availability_zone       = data.aws_availability_zones.available.names[2]
  map_public_ip_on_launch = true

  tags = {
    Name = "msk-subnet-3"
  }
}

resource "aws_route_table_association" "msk_subnet_1_assoc" {
  subnet_id      = aws_subnet.msk_subnet_1.id
  route_table_id = aws_route_table.msk_public_rt.id
}

resource "aws_route_table_association" "msk_subnet_2_assoc" {
  subnet_id      = aws_subnet.msk_subnet_2.id
  route_table_id = aws_route_table.msk_public_rt.id
}

resource "aws_route_table_association" "msk_subnet_3_assoc" {
  subnet_id      = aws_subnet.msk_subnet_3.id
  route_table_id = aws_route_table.msk_public_rt.id
}

resource "aws_security_group" "msk_sg" {
  name        = "msk-security-group"
  description = "Security group for MSK brokers"
  vpc_id      = aws_vpc.msk_vpc.id

  ingress {
    description = "Allow Kafka plaintext traffic within VPC"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk_vpc.cidr_block]
  }

  ingress {
    description = "Allow Kafka TLS traffic within VPC"
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk_vpc.cidr_block]
  }

  ingress {
    description = "Allow Kafka IAM authenticated traffic within VPC"
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk_vpc.cidr_block]
  }

  ingress {
    description = "Allow Zookeeper plaintext traffic within VPC"
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

  ingress {
    description = "Allow broker-to-broker and internal VPC traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
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

resource "aws_msk_cluster" "msk_cluster" {
  cluster_name           = var.cluster_name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type = var.broker_instance_type

    client_subnets = [
      aws_subnet.msk_subnet_1.id,
      aws_subnet.msk_subnet_2.id,
      aws_subnet.msk_subnet_3.id
    ]

    security_groups = [
      aws_security_group.msk_sg.id
    ]

    storage_info {
      ebs_storage_info {
        volume_size = var.broker_ebs_volume_size
      }
    }
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

  tags = {
    Name = var.cluster_name
  }
}

output "msk_cluster_arn" {
  description = "ARN of the MSK cluster"
  value       = aws_msk_cluster.msk_cluster.arn
}

output "msk_cluster_name" {
  description = "Name of the MSK cluster"
  value       = aws_msk_cluster.msk_cluster.cluster_name
}

output "bootstrap_brokers_plaintext" {
  description = "Plaintext bootstrap broker connection string"
  value       = aws_msk_cluster.msk_cluster.bootstrap_brokers
}

output "bootstrap_brokers_tls" {
  description = "TLS bootstrap broker connection string"
  value       = aws_msk_cluster.msk_cluster.bootstrap_brokers_tls
}

output "zookeeper_connect_string" {
  description = "Apache Zookeeper connection string"
  value       = aws_msk_cluster.msk_cluster.zookeeper_connect_string
}
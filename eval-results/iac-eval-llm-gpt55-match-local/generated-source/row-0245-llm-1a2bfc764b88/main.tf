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
  description = "AWS region where the Neptune cluster will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "example-neptune"
}

variable "vpc_cidr" {
  description = "CIDR block for the Neptune VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "neptune_subnet_1_cidr" {
  description = "CIDR block for the first Neptune subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "neptune_subnet_2_cidr" {
  description = "CIDR block for the second Neptune subnet."
  type        = string
  default     = "10.0.2.0/24"
}

variable "example_client_subnet_cidr" {
  description = "CIDR block for the example subnet allowed to connect to Neptune."
  type        = string
  default     = "10.0.10.0/24"
}

variable "neptune_instance_class" {
  description = "Instance class for the Neptune DB instance."
  type        = string
  default     = "db.t3.medium"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "neptune_1" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.neptune_subnet_1_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-neptune-subnet-1"
  }
}

resource "aws_subnet" "neptune_2" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.neptune_subnet_2_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-neptune-subnet-2"
  }
}

resource "aws_subnet" "example_client" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.example_client_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-example-client-subnet"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "neptune_1" {
  subnet_id      = aws_subnet.neptune_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "neptune_2" {
  subnet_id      = aws_subnet.neptune_2.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "example_client" {
  subnet_id      = aws_subnet.example_client.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "neptune" {
  name        = "${var.project_name}-sg"
  description = "Allow Neptune connections only from the example client subnet"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "Allow Neptune Gremlin/SPARQL/openCypher traffic from example subnet only"
    from_port   = 8182
    to_port     = 8182
    protocol    = "tcp"
    cidr_blocks = [var.example_client_subnet_cidr]
  }

  egress {
    description = "Allow all outbound traffic from Neptune"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-sg"
  }
}

resource "aws_neptune_subnet_group" "this" {
  name        = "${var.project_name}-subnet-group"
  description = "Subnet group for the Neptune cluster"

  subnet_ids = [
    aws_subnet.neptune_1.id,
    aws_subnet.neptune_2.id
  ]

  tags = {
    Name = "${var.project_name}-subnet-group"
  }
}

resource "aws_neptune_cluster_parameter_group" "this" {
  name        = "${var.project_name}-cluster-parameter-group"
  family      = "neptune1.2"
  description = "Custom Neptune cluster parameter group"

  tags = {
    Name = "${var.project_name}-cluster-parameter-group"
  }
}

resource "aws_neptune_parameter_group" "this" {
  name        = "${var.project_name}-instance-parameter-group"
  family      = "neptune1.2"
  description = "Custom Neptune instance parameter group"

  tags = {
    Name = "${var.project_name}-instance-parameter-group"
  }
}

resource "aws_neptune_cluster" "this" {
  cluster_identifier                  = "${var.project_name}-cluster"
  engine                              = "neptune"
  engine_version                      = "1.2.1.0"
  neptune_cluster_parameter_group_name = aws_neptune_cluster_parameter_group.this.name
  neptune_subnet_group_name            = aws_neptune_subnet_group.this.name
  vpc_security_group_ids               = [aws_security_group.neptune.id]

  storage_encrypted                   = true
  iam_database_authentication_enabled = false
  skip_final_snapshot                 = true
  deletion_protection                 = false
  apply_immediately                   = true

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

resource "aws_neptune_cluster_instance" "this" {
  identifier                  = "${var.project_name}-instance-1"
  cluster_identifier          = aws_neptune_cluster.this.id
  engine                      = "neptune"
  engine_version              = aws_neptune_cluster.this.engine_version
  instance_class              = var.neptune_instance_class
  neptune_parameter_group_name = aws_neptune_parameter_group.this.name
  neptune_subnet_group_name    = aws_neptune_subnet_group.this.name

  publicly_accessible = false
  apply_immediately   = true

  tags = {
    Name = "${var.project_name}-instance-1"
  }
}

output "neptune_cluster_endpoint" {
  description = "Writer endpoint for the Neptune cluster."
  value       = aws_neptune_cluster.this.endpoint
}

output "neptune_cluster_reader_endpoint" {
  description = "Reader endpoint for the Neptune cluster."
  value       = aws_neptune_cluster.this.reader_endpoint
}

output "neptune_instance_endpoint" {
  description = "Endpoint for the Neptune instance."
  value       = aws_neptune_cluster_instance.this.endpoint
}

output "allowed_example_client_subnet_id" {
  description = "ID of the example subnet allowed to connect to Neptune."
  value       = aws_subnet.example_client.id
}

output "allowed_example_client_subnet_cidr" {
  description = "CIDR block allowed to connect to the Neptune instance on port 8182."
  value       = var.example_client_subnet_cidr
}
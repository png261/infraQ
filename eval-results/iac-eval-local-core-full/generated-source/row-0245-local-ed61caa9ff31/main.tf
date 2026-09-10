terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "example-neptune-vpc"
  }
}

resource "aws_subnet" "example_source" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "example-neptune-source-subnet"
  }
}

resource "aws_subnet" "neptune_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.20.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "example-neptune-subnet-a"
  }
}

resource "aws_subnet" "neptune_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.21.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "example-neptune-subnet-b"
  }
}

resource "aws_security_group" "neptune" {
  name        = "example-neptune-sg"
  description = "Allow Neptune access only from the example source subnet"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Neptune from example source subnet"
    from_port   = 8182
    to_port     = 8182
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.example_source.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "example-neptune-sg"
  }
}

resource "aws_neptune_subnet_group" "example" {
  name = "example-neptune-subnet-group"
  subnet_ids = [
    aws_subnet.example_source.id,
    aws_subnet.neptune_a.id,
    aws_subnet.neptune_b.id,
  ]

  tags = {
    Name = "example-neptune-subnet-group"
  }
}

resource "aws_neptune_cluster_parameter_group" "example" {
  name        = "example-neptune-cluster-parameter-group"
  family      = "neptune1.2"
  description = "Example Neptune cluster parameter group"

  parameter {
    name  = "neptune_enable_audit_log"
    value = "1"
  }
}

resource "aws_neptune_parameter_group" "example" {
  name        = "example-neptune-instance-parameter-group"
  family      = "neptune1.2"
  description = "Example Neptune instance parameter group"
}

resource "aws_neptune_cluster" "example" {
  cluster_identifier                   = "example-neptune-cluster"
  engine                               = "neptune"
  neptune_cluster_parameter_group_name = aws_neptune_cluster_parameter_group.example.name
  neptune_subnet_group_name            = aws_neptune_subnet_group.example.name
  vpc_security_group_ids               = [aws_security_group.neptune.id]
  skip_final_snapshot                  = true

  tags = {
    Name = "example-neptune-cluster"
  }
}

resource "aws_neptune_cluster_instance" "example" {
  identifier                   = "example-neptune-instance-1"
  cluster_identifier           = aws_neptune_cluster.example.id
  engine                       = "neptune"
  instance_class               = "db.t3.medium"
  neptune_parameter_group_name = aws_neptune_parameter_group.example.name
  neptune_subnet_group_name    = aws_neptune_subnet_group.example.name

  tags = {
    Name = "example-neptune-instance-1"
  }
}

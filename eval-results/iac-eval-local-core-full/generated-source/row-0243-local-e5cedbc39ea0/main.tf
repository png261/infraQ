resource "aws_vpc" "neptune" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "example-neptune-vpc"
  }
}

resource "aws_subnet" "neptune_a" {
  vpc_id            = aws_vpc.neptune.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "example-neptune-subnet-a"
  }
}

resource "aws_subnet" "neptune_b" {
  vpc_id            = aws_vpc.neptune.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "example-neptune-subnet-b"
  }
}

resource "aws_neptune_subnet_group" "example" {
  name       = "example-neptune-subnet-group"
  subnet_ids = [aws_subnet.neptune_a.id, aws_subnet.neptune_b.id]

  tags = {
    Name = "example-neptune-subnet-group"
  }
}

resource "aws_neptune_cluster_parameter_group" "example" {
  name   = "example-neptune-parameter-group"
  family = "neptune1.2"

  parameter {
    name  = "neptune_enable_audit_log"
    value = "1"
  }

  tags = {
    Name = "example-neptune-parameter-group"
  }
}

resource "aws_neptune_cluster" "example" {
  cluster_identifier                  = "example-neptune-cluster"
  engine                              = "neptune"
  neptune_cluster_parameter_group_name = aws_neptune_cluster_parameter_group.example.name
  neptune_subnet_group_name           = aws_neptune_subnet_group.example.name
  skip_final_snapshot                 = true

  tags = {
    Name = "example-neptune-cluster"
  }
}

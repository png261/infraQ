resource "aws_vpc" "example" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "example-neptune-vpc"
  }
}

resource "aws_subnet" "example_a" {
  vpc_id            = aws_vpc.example.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "example-neptune-subnet-a"
  }
}

resource "aws_subnet" "example_b" {
  vpc_id            = aws_vpc.example.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "example-neptune-subnet-b"
  }
}

resource "aws_neptune_subnet_group" "example" {
  name       = "example-neptune-subnet-group"
  subnet_ids = [aws_subnet.example_a.id, aws_subnet.example_b.id]

  tags = {
    Name = "example-neptune-subnet-group"
  }
}

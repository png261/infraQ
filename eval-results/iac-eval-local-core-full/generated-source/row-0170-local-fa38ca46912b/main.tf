resource "aws_vpc" "dax" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "custom-dax-vpc"
  }
}

resource "aws_subnet" "dax_a" {
  vpc_id            = aws_vpc.dax.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "custom-dax-subnet-a"
  }
}

resource "aws_subnet" "dax_b" {
  vpc_id            = aws_vpc.dax.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "custom-dax-subnet-b"
  }
}

resource "aws_dax_subnet_group" "custom" {
  name        = "custom-dax-subnet-group"
  description = "Custom DAX subnet group spanning two subnets"
  subnet_ids  = [aws_subnet.dax_a.id, aws_subnet.dax_b.id]
}

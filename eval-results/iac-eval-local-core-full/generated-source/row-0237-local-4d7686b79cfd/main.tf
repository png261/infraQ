resource "aws_vpc" "benchmark" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "benchmark-vpc"
  }
}

resource "aws_subnet" "benchmark" {
  vpc_id                  = aws_vpc.benchmark.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "benchmark-subnet"
  }
}

resource "aws_network_acl" "benchmark" {
  vpc_id     = aws_vpc.benchmark.id
  subnet_ids = [aws_subnet.benchmark.id]

  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "10.0.0.0/16"
    from_port  = 80
    to_port    = 80
  }

  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "benchmark-network-acl"
  }
}

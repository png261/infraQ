locals {
  vpc_cidr_block = "10.0.0.0/16"

  public_subnets = {
    public_1 = {
      cidr_block        = "10.0.1.0/24"
      availability_zone = "us-east-1a"
      name              = "benchmark-public-subnet-1"
    }
    public_2 = {
      cidr_block        = "10.0.2.0/24"
      availability_zone = "us-east-1b"
      name              = "benchmark-public-subnet-2"
    }
    public_3 = {
      cidr_block        = "10.0.3.0/24"
      availability_zone = "us-east-1c"
      name              = "benchmark-public-subnet-3"
    }
  }
}

resource "aws_vpc" "main" {
  cidr_block           = local.vpc_cidr_block
  enable_dns_hostnames = true

  tags = {
    Name = "benchmark-vpc"
  }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr_block
  availability_zone       = each.value.availability_zone
  map_public_ip_on_launch = true

  tags = {
    Name = each.value.name
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "benchmark-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "benchmark-public-route-table"
  }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

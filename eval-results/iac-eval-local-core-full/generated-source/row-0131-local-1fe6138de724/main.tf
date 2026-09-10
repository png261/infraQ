data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "benchmark-vpc"
  }
}

resource "aws_internet_gateway" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "benchmark-public-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "benchmark-public-subnet"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.public.id
  }

  tags = {
    Name = "benchmark-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "benchmark-private-subnet"
  }
}

resource "aws_security_group" "instances" {
  name        = "benchmark-cluster-instances"
  description = "Allow intra-cluster traffic for benchmark EC2 instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow all traffic between cluster instances"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "benchmark-cluster-sg"
  }
}

resource "aws_placement_group" "cluster" {
  name     = "benchmark-cluster-placement-group"
  strategy = "cluster"
}

resource "aws_instance" "cluster" {
  count = 3

  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "c5.large"
  subnet_id              = aws_subnet.private.id
  vpc_security_group_ids = [aws_security_group.instances.id]
  placement_group        = aws_placement_group.cluster.name

  tags = {
    Name = "benchmark-cluster-${count.index + 1}"
  }
}

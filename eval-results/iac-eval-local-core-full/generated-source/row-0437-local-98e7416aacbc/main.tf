resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "iac-eval-vpc"
  }
}

resource "aws_subnet" "az_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-west-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "iac-eval-subnet-a"
  }
}

resource "aws_subnet" "az_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-west-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "iac-eval-subnet-b"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "iac-eval-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "iac-eval-public-rt"
  }
}

resource "aws_route_table_association" "az_a" {
  subnet_id      = aws_subnet.az_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "az_b" {
  subnet_id      = aws_subnet.az_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "database" {
  name        = "iac-eval-database-sg"
  description = "Allow MySQL and PostgreSQL access from anywhere"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "MySQL"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "PostgreSQL"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "iac-eval-database-sg"
  }
}

resource "aws_db_subnet_group" "database" {
  name       = "iac-eval-db-subnet-group"
  subnet_ids = [aws_subnet.az_a.id, aws_subnet.az_b.id]

  tags = {
    Name = "iac-eval-db-subnet-group"
  }
}

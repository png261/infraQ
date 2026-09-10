terraform {
  required_version = ">= 1.5.0"

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
    Name = "iac-eval-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "iac-eval-igw"
  }
}

resource "aws_subnet" "public_web" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "iac-eval-public-web"
    Tier = "public"
  }
}

resource "aws_subnet" "private_app" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "iac-eval-private-app"
    Tier = "private"
  }
}

resource "aws_subnet" "private_db" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "iac-eval-private-db"
    Tier = "private"
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

resource "aws_route_table_association" "public_web" {
  subnet_id      = aws_subnet.public_web.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  name        = "iac-eval-web-sg"
  description = "Allow public HTTP access to the web server"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "iac-eval-web-sg"
  }
}

resource "aws_security_group" "app" {
  name        = "iac-eval-app-sg"
  description = "Allow application traffic from the web server"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Application traffic from web server"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.web.id]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "iac-eval-app-sg"
  }
}

resource "aws_security_group" "db" {
  name        = "iac-eval-db-sg"
  description = "Allow database traffic from the application server"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from application server"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  tags = {
    Name = "iac-eval-db-sg"
  }
}

resource "aws_instance" "web" {
  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public_web.id
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    dnf install -y httpd
    systemctl enable --now httpd
    echo "webserver" > /var/www/html/index.html
  EOF

  tags = {
    Name = "iac-eval-webserver"
    Role = "webserver"
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.private_app.id
  vpc_security_group_ids = [aws_security_group.app.id]

  tags = {
    Name = "iac-eval-application-server"
    Role = "application"
  }
}

resource "aws_db_subnet_group" "database" {
  name       = "iac-eval-db-subnet-group"
  subnet_ids = [aws_subnet.private_app.id, aws_subnet.private_db.id]

  tags = {
    Name = "iac-eval-db-subnet-group"
  }
}

resource "aws_db_instance" "database" {
  identifier                  = "iac-eval-database"
  allocated_storage           = 20
  engine                      = "mysql"
  instance_class              = "db.t3.micro"
  db_name                     = "appdb"
  username                    = "appadmin"
  manage_master_user_password = true
  db_subnet_group_name        = aws_db_subnet_group.database.name
  vpc_security_group_ids      = [aws_security_group.db.id]
  publicly_accessible         = false
  skip_final_snapshot         = true
  deletion_protection         = false

  tags = {
    Name = "iac-eval-relational-database"
    Role = "database"
  }
}

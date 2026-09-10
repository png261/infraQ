resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "iac-eval-postgres-vpc"
  }
}

resource "aws_subnet" "database_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "iac-eval-postgres-subnet-a"
  }
}

resource "aws_subnet" "database_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "iac-eval-postgres-subnet-b"
  }
}

resource "aws_db_subnet_group" "postgres" {
  name = "iac-eval-postgres-subnet-group"
  subnet_ids = [
    aws_subnet.database_a.id,
    aws_subnet.database_b.id,
  ]

  tags = {
    Name = "iac-eval-postgres-subnet-group"
  }
}

resource "aws_db_instance" "postgres" {
  identifier              = "iac-eval-postgres"
  allocated_storage       = 20
  engine                  = "postgres"
  engine_version          = "16.3"
  instance_class          = "db.t3.micro"
  db_name                 = "iac_eval"
  username                = var.db_username
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.postgres.name
  backup_retention_period = 5
  backup_window           = "03:00-06:00"
  skip_final_snapshot     = true
  publicly_accessible     = false
}

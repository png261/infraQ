terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "random_password" "db_password" {
  length  = 20
  special = false
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main"
  }
}

resource "aws_subnet" "db_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "main-db-a"
  }
}

resource "aws_subnet" "db_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "main-db-b"
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "main-db-subnet-group-${random_id.suffix.hex}"
  subnet_ids = [
    aws_subnet.db_a.id,
    aws_subnet.db_b.id
  ]

  tags = {
    Name = "main-db-subnet-group"
  }
}

resource "aws_security_group" "db" {
  name        = "main-db-sg-${random_id.suffix.hex}"
  description = "Security group for primary and replica RDS instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow MySQL traffic from within the VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [
      aws_vpc.main.cidr_block
    ]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  tags = {
    Name = "main-db-sg"
  }
}

resource "aws_route53_zone" "main" {
  name = "main"

  vpc {
    vpc_id = aws_vpc.main.id
  }

  tags = {
    Name = "main"
  }
}

resource "aws_db_instance" "primary" {
  identifier = "primary-${random_id.suffix.hex}"

  allocated_storage      = 20
  max_allocated_storage  = 100
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = "maindb"
  username               = "adminuser"
  password               = random_password.db_password.result
  port                   = 3306
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  publicly_accessible     = false
  multi_az                = false
  storage_encrypted       = true
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  tags = {
    Name = "primary"
  }
}

resource "aws_db_instance" "replica_1" {
  identifier = "replica-1-${random_id.suffix.hex}"

  replicate_source_db    = aws_db_instance.primary.identifier
  instance_class         = "db.t3.micro"
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.db.id]

  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true

  tags = {
    Name = "replica-1"
  }

  depends_on = [
    aws_db_instance.primary
  ]
}

resource "aws_db_instance" "replica_2" {
  identifier = "replica-2-${random_id.suffix.hex}"

  replicate_source_db    = aws_db_instance.primary.identifier
  instance_class         = "db.t3.micro"
  publicly_accessible    = false
  vpc_security_group_ids = [aws_security_group.db.id]

  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true

  tags = {
    Name = "replica-2"
  }

  depends_on = [
    aws_db_instance.primary
  ]
}

resource "aws_route53_record" "replica_1_weighted" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "db.main"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "replica-1"

  weighted_routing_policy {
    weight = 50
  }

  records = [
    aws_db_instance.replica_1.address
  ]
}

resource "aws_route53_record" "replica_2_weighted" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "db.main"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "replica-2"

  weighted_routing_policy {
    weight = 50
  }

  records = [
    aws_db_instance.replica_2.address
  ]
}

output "primary_db_endpoint" {
  value = aws_db_instance.primary.endpoint
}

output "replica_1_db_endpoint" {
  value = aws_db_instance.replica_1.endpoint
}

output "replica_2_db_endpoint" {
  value = aws_db_instance.replica_2.endpoint
}

output "weighted_route53_record" {
  value = aws_route53_record.replica_1_weighted.fqdn
}
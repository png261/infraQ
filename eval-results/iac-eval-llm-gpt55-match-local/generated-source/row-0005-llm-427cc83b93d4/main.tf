terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type        = string
  description = "AWS region to deploy resources into."
  default     = "us-east-1"
}

variable "db_username" {
  type        = string
  description = "Master username for the primary RDS instance."
  default     = "adminuser"
}

variable "db_password" {
  type        = string
  description = "Master password for the primary RDS instance."
  default     = "ChangeMe12345!"
  sensitive   = true
}

variable "db_name" {
  type        = string
  description = "Initial database name."
  default     = "maindb"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main"
  }
}

resource "aws_subnet" "main_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "main-a"
  }
}

resource "aws_subnet" "main_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "main-b"
  }
}

resource "aws_db_subnet_group" "main" {
  name       = "main-db-subnet-group"
  subnet_ids = [
    aws_subnet.main_a.id,
    aws_subnet.main_b.id
  ]

  tags = {
    Name = "main-db-subnet-group"
  }
}

resource "aws_security_group" "db" {
  name        = "main-db-sg"
  description = "Security group for RDS database instances"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow MySQL access from within the VPC"
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

resource "aws_db_instance" "primary" {
  identifier = "primary"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  publicly_accessible = false
  multi_az            = false

  deletion_protection = false
  skip_final_snapshot = true

  tags = {
    Name = "primary"
  }
}

resource "aws_db_instance" "replica_1" {
  identifier = "replica-1"

  replicate_source_db = aws_db_instance.primary.identifier

  instance_class = "db.t3.micro"

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  publicly_accessible = false
  multi_az            = false

  deletion_protection = false
  skip_final_snapshot = true

  depends_on = [
    aws_db_instance.primary
  ]

  tags = {
    Name = "replica-1"
  }
}

resource "aws_db_instance" "replica_2" {
  identifier = "replica-2"

  replicate_source_db = aws_db_instance.primary.identifier

  instance_class = "db.t3.micro"

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  publicly_accessible = false
  multi_az            = false

  deletion_protection = false
  skip_final_snapshot = true

  depends_on = [
    aws_db_instance.primary
  ]

  tags = {
    Name = "replica-2"
  }
}

resource "aws_route53_zone" "main" {
  name = "main"

  vpc {
    vpc_id = aws_vpc.main.id
  }

  comment = "Private hosted zone named main for weighted DB replica routing"

  tags = {
    Name = "main"
  }
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

output "primary_endpoint" {
  description = "Primary RDS endpoint."
  value       = aws_db_instance.primary.endpoint
}

output "replica_1_endpoint" {
  description = "Replica 1 RDS endpoint."
  value       = aws_db_instance.replica_1.endpoint
}

output "replica_2_endpoint" {
  description = "Replica 2 RDS endpoint."
  value       = aws_db_instance.replica_2.endpoint
}

output "weighted_database_dns_name" {
  description = "Route 53 weighted DNS name that splits traffic between replica-1 and replica-2."
  value       = "db.main"
}
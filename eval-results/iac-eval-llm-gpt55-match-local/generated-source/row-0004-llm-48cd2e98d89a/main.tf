terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "DNS zone name used for split-horizon Route 53 resolution."
  type        = string
  default     = "example.com"
}

variable "database_record_name" {
  description = "Database DNS record name."
  type        = string
  default     = "database"
}

variable "db_username" {
  description = "Master username for both RDS instances."
  type        = string
  default     = "adminuser"
}

resource "random_password" "db_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

data "aws_availability_zones" "available" {
  state = "available"
}

# -----------------------------
# Networking
# -----------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "main"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-b"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.11.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.12.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "private-b"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "public"
  }
}

resource "aws_route" "public_default_ipv4" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "private"
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# -----------------------------
# Security Groups
# -----------------------------

resource "aws_security_group" "internal_db" {
  name        = "internal-db"
  description = "Allow MySQL access to the internal RDS instance from inside the VPC."
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "MySQL from VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "internal-db"
  }
}

resource "aws_security_group" "public_db" {
  name        = "public-db"
  description = "Allow MySQL access to the public RDS instance from external clients."
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "MySQL from the internet"
    from_port   = 3306
    to_port     = 3306
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
    Name = "public-db"
  }
}

# -----------------------------
# RDS Subnet Groups
# -----------------------------

resource "aws_db_subnet_group" "main" {
  name        = "main"
  description = "Main DB subnet group for internal and public databases."

  subnet_ids = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id,
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  tags = {
    Name = "main"
  }
}

# -----------------------------
# RDS Databases
# -----------------------------

resource "aws_db_instance" "internal" {
  identifier              = "internal"
  allocated_storage       = 20
  max_allocated_storage   = 100
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  db_name                 = "internal"
  username                = var.db_username
  password                = random_password.db_password.result
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.internal_db.id]
  publicly_accessible     = false
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 0
  multi_az                = false

  tags = {
    Name = "internal"
  }
}

resource "aws_db_instance" "public" {
  identifier              = "public"
  allocated_storage       = 20
  max_allocated_storage   = 100
  engine                  = "mysql"
  engine_version          = "8.0"
  instance_class          = "db.t3.micro"
  db_name                 = "public"
  username                = var.db_username
  password                = random_password.db_password.result
  db_subnet_group_name    = aws_db_subnet_group.main.name
  vpc_security_group_ids  = [aws_security_group.public_db.id]
  publicly_accessible     = true
  skip_final_snapshot     = true
  deletion_protection     = false
  backup_retention_period = 0
  multi_az                = false

  tags = {
    Name = "public"
  }
}

# -----------------------------
# Route 53 Split-Horizon DNS
# -----------------------------

resource "aws_route53_zone" "private" {
  name = var.domain_name

  vpc {
    vpc_id = aws_vpc.main.id
  }

  comment = "Private hosted zone named private for internal database resolution."

  tags = {
    Name = "private"
  }
}

resource "aws_route53_zone" "public" {
  name = var.domain_name

  comment = "Public hosted zone named public for external database resolution."

  tags = {
    Name = "public"
  }
}

resource "aws_route53_record" "internal_database" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "${var.database_record_name}.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60

  records = [
    aws_db_instance.internal.address
  ]
}

resource "aws_route53_record" "public_database" {
  zone_id = aws_route53_zone.public.zone_id
  name    = "${var.database_record_name}.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60

  records = [
    aws_db_instance.public.address
  ]
}

# -----------------------------
# Outputs
# -----------------------------

output "private_zone_id" {
  description = "Private Route 53 hosted zone ID."
  value       = aws_route53_zone.private.zone_id
}

output "public_zone_id" {
  description = "Public Route 53 hosted zone ID."
  value       = aws_route53_zone.public.zone_id
}

output "database_dns_name" {
  description = "The split-horizon database DNS name. Internal VPC users resolve to the internal DB; external users resolve to the public DB."
  value       = "${var.database_record_name}.${var.domain_name}"
}

output "internal_rds_endpoint" {
  description = "Internal RDS endpoint."
  value       = aws_db_instance.internal.endpoint
}

output "public_rds_endpoint" {
  description = "Public RDS endpoint."
  value       = aws_db_instance.public.endpoint
}

output "db_username" {
  description = "Database master username."
  value       = var.db_username
}

output "db_password" {
  description = "Database master password."
  value       = random_password.db_password.result
  sensitive   = true
}
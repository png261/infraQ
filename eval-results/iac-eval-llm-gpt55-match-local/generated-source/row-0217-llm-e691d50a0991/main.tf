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
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the MySQL cluster will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "db_username" {
  description = "Master username for the primary MySQL database."
  type        = string
  default     = "adminuser"
}

variable "db_password" {
  description = "Master password for the primary MySQL database."
  type        = string
  sensitive   = true
  default     = "ChangeMe12345!"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "appdb"
}

variable "db_instance_class" {
  description = "Instance class for each MySQL instance."
  type        = string
  default     = "db.t3.medium"
}

variable "allocated_storage_gb" {
  description = "Storage allocated to each MySQL instance in each Availability Zone."
  type        = number
  default     = 100
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  selected_azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

resource "aws_vpc" "mysql_vpc" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "mysql-cluster-vpc"
  }
}

resource "aws_subnet" "mysql_subnets" {
  count = 3

  vpc_id                  = aws_vpc.mysql_vpc.id
  cidr_block              = cidrsubnet(aws_vpc.mysql_vpc.cidr_block, 8, count.index)
  availability_zone       = local.selected_azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "mysql-subnet-${count.index + 1}-${local.selected_azs[count.index]}"
  }
}

resource "aws_db_subnet_group" "mysql_subnet_group" {
  name       = "mysql-cluster-subnet-group"
  subnet_ids = aws_subnet.mysql_subnets[*].id

  tags = {
    Name = "mysql-cluster-subnet-group"
  }
}

resource "aws_security_group" "mysql_sg" {
  name        = "mysql-cluster-sg"
  description = "Allow MySQL access from inside the VPC"
  vpc_id      = aws_vpc.mysql_vpc.id

  ingress {
    description = "MySQL from VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.mysql_vpc.cidr_block]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "mysql-cluster-sg"
  }
}

resource "aws_db_parameter_group" "mysql_parameter_group" {
  name        = "mysql-cluster-parameter-group"
  family      = "mysql8.0"
  description = "Parameter group for MySQL cluster instances"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  tags = {
    Name = "mysql-cluster-parameter-group"
  }
}

resource "aws_db_instance" "mysql_primary" {
  identifier = "mysql-primary-zone-1"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.db_instance_class

  allocated_storage = var.allocated_storage_gb
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  availability_zone      = local.selected_azs[0]
  db_subnet_group_name   = aws_db_subnet_group.mysql_subnet_group.name
  vpc_security_group_ids = [aws_security_group.mysql_sg.id]
  parameter_group_name   = aws_db_parameter_group.mysql_parameter_group.name

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  publicly_accessible = false
  multi_az            = false

  auto_minor_version_upgrade = true
  deletion_protection        = false
  skip_final_snapshot        = true

  tags = {
    Name = "mysql-primary-zone-1"
    Role = "primary"
    Zone = local.selected_azs[0]
  }
}

resource "aws_db_instance" "mysql_replica_zone_2" {
  identifier = "mysql-replica-zone-2"

  replicate_source_db = aws_db_instance.mysql_primary.identifier

  instance_class = var.db_instance_class

  allocated_storage = var.allocated_storage_gb
  storage_type      = "gp3"
  storage_encrypted = true

  availability_zone      = local.selected_azs[1]
  vpc_security_group_ids = [aws_security_group.mysql_sg.id]
  parameter_group_name   = aws_db_parameter_group.mysql_parameter_group.name

  publicly_accessible = false
  multi_az            = false

  auto_minor_version_upgrade = true
  deletion_protection        = false
  skip_final_snapshot        = true

  depends_on = [
    aws_db_instance.mysql_primary
  ]

  tags = {
    Name = "mysql-replica-zone-2"
    Role = "read-replica"
    Zone = local.selected_azs[1]
  }
}

resource "aws_db_instance" "mysql_replica_zone_3" {
  identifier = "mysql-replica-zone-3"

  replicate_source_db = aws_db_instance.mysql_primary.identifier

  instance_class = var.db_instance_class

  allocated_storage = var.allocated_storage_gb
  storage_type      = "gp3"
  storage_encrypted = true

  availability_zone      = local.selected_azs[2]
  vpc_security_group_ids = [aws_security_group.mysql_sg.id]
  parameter_group_name   = aws_db_parameter_group.mysql_parameter_group.name

  publicly_accessible = false
  multi_az            = false

  auto_minor_version_upgrade = true
  deletion_protection        = false
  skip_final_snapshot        = true

  depends_on = [
    aws_db_instance.mysql_primary
  ]

  tags = {
    Name = "mysql-replica-zone-3"
    Role = "read-replica"
    Zone = local.selected_azs[2]
  }
}

output "mysql_primary_endpoint" {
  description = "Primary MySQL writer endpoint."
  value       = aws_db_instance.mysql_primary.address
}

output "mysql_replica_zone_2_endpoint" {
  description = "Read replica endpoint in the second Availability Zone."
  value       = aws_db_instance.mysql_replica_zone_2.address
}

output "mysql_replica_zone_3_endpoint" {
  description = "Read replica endpoint in the third Availability Zone."
  value       = aws_db_instance.mysql_replica_zone_3.address
}

output "mysql_port" {
  description = "MySQL port."
  value       = 3306
}

output "availability_zones" {
  description = "Availability Zones used by the MySQL deployment."
  value       = local.selected_azs
}

output "storage_per_zone_gb" {
  description = "Allocated MySQL storage per Availability Zone."
  value       = var.allocated_storage_gb
}
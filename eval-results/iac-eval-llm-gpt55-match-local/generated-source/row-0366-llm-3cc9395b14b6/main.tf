terraform {
  required_version = ">= 1.3.0"

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
  description = "AWS region where the Lightsail managed database will be created."
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Availability zone for the Lightsail database."
  type        = string
  default     = "us-east-1a"
}

variable "database_name" {
  description = "The Lightsail managed database resource name."
  type        = string
  default     = "lightsail-managed-db"
}

variable "master_database_name" {
  description = "The default database name to create."
  type        = string
  default     = "appdb"
}

variable "master_username" {
  description = "Master username for the database."
  type        = string
  default     = "dbadmin"
}

variable "master_password" {
  description = "Master password for the database. Must meet AWS Lightsail database password requirements."
  type        = string
  sensitive   = true
  default     = "SecurePassw0rd123"
}

variable "blueprint_id" {
  description = "The database engine blueprint ID."
  type        = string
  default     = "mysql_8_0"
}

variable "bundle_id" {
  description = "The Lightsail database bundle ID."
  type        = string
  default     = "micro_2_0"
}

resource "aws_lightsail_database" "managed_db" {
  relational_database_name = var.database_name
  availability_zone        = var.availability_zone

  master_database_name = var.master_database_name
  master_username      = var.master_username
  master_password      = var.master_password

  blueprint_id = var.blueprint_id
  bundle_id    = var.bundle_id

  publicly_accessible = true
  apply_immediately   = true
  skip_final_snapshot = true

  preferred_backup_window      = "07:00-08:00"
  preferred_maintenance_window = "sun:09:00-sun:10:00"

  tags = {
    Name        = var.database_name
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

output "lightsail_database_name" {
  description = "Name of the Lightsail managed database."
  value       = aws_lightsail_database.managed_db.relational_database_name
}

output "lightsail_database_endpoint" {
  description = "Endpoint address of the Lightsail managed database."
  value       = aws_lightsail_database.managed_db.master_endpoint_address
}

output "lightsail_database_port" {
  description = "Port of the Lightsail managed database."
  value       = aws_lightsail_database.managed_db.master_endpoint_port
}

output "lightsail_database_arn" {
  description = "ARN of the Lightsail managed database."
  value       = aws_lightsail_database.managed_db.arn
}
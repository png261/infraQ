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
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the Lightsail PostgreSQL database will be created."
  type        = string
  default     = "us-east-1"
}

variable "database_name" {
  description = "Name of the Lightsail relational database instance."
  type        = string
  default     = "lightsail-postgres-db"
}

variable "master_database_name" {
  description = "Name of the default PostgreSQL database to create."
  type        = string
  default     = "appdb"
}

variable "master_username" {
  description = "Master username for the PostgreSQL database."
  type        = string
  default     = "dbadmin"
}

variable "postgres_blueprint_id" {
  description = "Lightsail PostgreSQL blueprint ID."
  type        = string
  default     = "postgres_12"
}

variable "database_bundle_id" {
  description = "Lightsail database bundle ID."
  type        = string
  default     = "micro_2_0"
}

variable "availability_zone" {
  description = "Availability zone for the Lightsail database."
  type        = string
  default     = "us-east-1a"
}

variable "preferred_backup_window" {
  description = "Daily backup window in UTC."
  type        = string
  default     = "03:00-04:00"
}

variable "preferred_maintenance_window" {
  description = "Weekly maintenance window in UTC."
  type        = string
  default     = "sun:05:00-sun:06:00"
}

variable "publicly_accessible" {
  description = "Whether the Lightsail database should be publicly accessible."
  type        = bool
  default     = false
}

resource "random_password" "postgres_master_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_lightsail_database" "postgres" {
  relational_database_name = var.database_name
  availability_zone        = var.availability_zone

  master_database_name = var.master_database_name
  master_username      = var.master_username
  master_password      = random_password.postgres_master_password.result

  blueprint_id = var.postgres_blueprint_id
  bundle_id    = var.database_bundle_id

  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window

  publicly_accessible = var.publicly_accessible

  apply_immediately = true
  skip_final_snapshot = true

  tags = {
    Name        = var.database_name
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

output "database_name" {
  description = "The Lightsail PostgreSQL database name."
  value       = aws_lightsail_database.postgres.relational_database_name
}

output "database_arn" {
  description = "The ARN of the Lightsail PostgreSQL database."
  value       = aws_lightsail_database.postgres.arn
}

output "database_endpoint" {
  description = "The endpoint of the Lightsail PostgreSQL database."
  value       = aws_lightsail_database.postgres.master_endpoint_address
}

output "database_port" {
  description = "The port of the Lightsail PostgreSQL database."
  value       = aws_lightsail_database.postgres.master_endpoint_port
}

output "master_username" {
  description = "The master username for the PostgreSQL database."
  value       = var.master_username
}

output "master_password" {
  description = "The generated master password for the PostgreSQL database."
  value       = random_password.postgres_master_password.result
  sensitive   = true
}
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

variable "availability_zone" {
  description = "Availability Zone for the Lightsail database."
  type        = string
  default     = "us-east-1a"
}

variable "database_name" {
  description = "Name of the Lightsail relational database resource."
  type        = string
  default     = "lightsail-postgres-db"
}

variable "master_database_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "appdb"
}

variable "master_username" {
  description = "Master username for the PostgreSQL database."
  type        = string
  default     = "dbadmin"
}

variable "blueprint_id" {
  description = "Lightsail database blueprint ID for PostgreSQL."
  type        = string
  default     = "postgres_12"
}

variable "bundle_id" {
  description = "Lightsail database bundle ID."
  type        = string
  default     = "micro_1_0"
}

resource "random_password" "postgres_master_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "random_id" "final_snapshot_suffix" {
  byte_length = 4
}

resource "aws_lightsail_database" "postgres" {
  relational_database_name = var.database_name
  availability_zone        = var.availability_zone

  master_database_name = var.master_database_name
  master_username      = var.master_username
  master_password      = random_password.postgres_master_password.result

  blueprint_id = var.blueprint_id
  bundle_id    = var.bundle_id

  publicly_accessible = false
  apply_immediately   = true

  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:05:00-sun:06:00"

  skip_final_snapshot = false
  final_snapshot_name = "${var.database_name}-final-${random_id.final_snapshot_suffix.hex}"

  tags = {
    Name        = var.database_name
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

output "lightsail_database_name" {
  description = "The name of the Lightsail PostgreSQL database."
  value       = aws_lightsail_database.postgres.relational_database_name
}

output "lightsail_database_arn" {
  description = "The ARN of the Lightsail PostgreSQL database."
  value       = aws_lightsail_database.postgres.arn
}

output "master_username" {
  description = "The PostgreSQL master username."
  value       = var.master_username
}

output "master_password" {
  description = "The generated PostgreSQL master password."
  value       = random_password.postgres_master_password.result
  sensitive   = true
}

output "final_snapshot_name_on_delete" {
  description = "The final snapshot name that will be created when the database is deleted."
  value       = aws_lightsail_database.postgres.final_snapshot_name
}
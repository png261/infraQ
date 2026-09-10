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

provider "random" {}

variable "aws_region" {
  description = "AWS region where the Lightsail database will be created."
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Availability zone for the Lightsail database."
  type        = string
  default     = "us-east-1a"
}

variable "database_name" {
  description = "The name of the Lightsail relational database resource."
  type        = string
  default     = "mysql-lightsail-db"
}

variable "master_database_name" {
  description = "The initial database name created inside MySQL."
  type        = string
  default     = "appdb"
}

variable "master_username" {
  description = "The master username for the MySQL database."
  type        = string
  default     = "dbadmin"
}

variable "mysql_blueprint_id" {
  description = "The Lightsail database blueprint ID."
  type        = string
  default     = "mysql_8_0"
}

variable "database_bundle_id" {
  description = "The Lightsail database bundle ID."
  type        = string
  default     = "micro_2_0"
}

resource "random_password" "mysql_master_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}"
}

resource "aws_lightsail_database" "mysql" {
  relational_database_name = var.database_name
  availability_zone        = var.availability_zone

  master_database_name = var.master_database_name
  master_username      = var.master_username
  master_password      = random_password.mysql_master_password.result

  blueprint_id = var.mysql_blueprint_id
  bundle_id    = var.database_bundle_id

  preferred_backup_window      = "16:00-16:30"
  preferred_maintenance_window = "Tue:17:00-Tue:17:30"

  apply_immediately  = false
  skip_final_snapshot = false

  tags = {
    Name        = var.database_name
    Environment = "production"
    ManagedBy   = "terraform"
  }
}

output "lightsail_database_name" {
  description = "The name of the Lightsail MySQL database."
  value       = aws_lightsail_database.mysql.relational_database_name
}

output "lightsail_database_arn" {
  description = "The ARN of the Lightsail MySQL database."
  value       = aws_lightsail_database.mysql.arn
}

output "lightsail_database_endpoint" {
  description = "The endpoint address of the Lightsail MySQL database."
  value       = aws_lightsail_database.mysql.master_endpoint_address
}

output "lightsail_database_port" {
  description = "The port of the Lightsail MySQL database."
  value       = aws_lightsail_database.mysql.master_endpoint_port
}

output "mysql_master_username" {
  description = "The master username for the MySQL database."
  value       = var.master_username
}

output "mysql_master_password" {
  description = "The generated master password for the MySQL database."
  value       = random_password.mysql_master_password.result
  sensitive   = true
}
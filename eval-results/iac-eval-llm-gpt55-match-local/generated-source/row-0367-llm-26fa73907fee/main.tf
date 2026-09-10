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
  description = "AWS region where Lightsail resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Availability zone for the Lightsail instance."
  type        = string
  default     = "us-east-1a"
}

variable "instance_name" {
  description = "Name of the Lightsail instance."
  type        = string
  default     = "mysql-app-lightsail-instance"
}

variable "database_name" {
  description = "Name of the Lightsail MySQL database resource."
  type        = string
  default     = "mysql-lightsail-database"
}

variable "master_database_name" {
  description = "Initial database name created in the Lightsail MySQL database."
  type        = string
  default     = "appdb"
}

variable "master_username" {
  description = "Master username for the Lightsail MySQL database."
  type        = string
  default     = "dbadmin"
}

variable "master_password" {
  description = "Master password for the Lightsail MySQL database."
  type        = string
  sensitive   = true
  default     = "ChangeMe12345!"
}

resource "aws_lightsail_database" "mysql" {
  relational_database_name = var.database_name
  availability_zone        = var.availability_zone

  blueprint_id = "mysql_8_0"
  bundle_id    = "micro_2_0"

  master_database_name = var.master_database_name
  master_username      = var.master_username
  master_password      = var.master_password

  publicly_accessible = false

  apply_immediately = true

  tags = {
    Name        = var.database_name
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

resource "aws_lightsail_instance" "app" {
  name              = var.instance_name
  availability_zone = var.availability_zone

  blueprint_id = "amazon_linux_2023"
  bundle_id    = "nano_3_0"

  user_data = <<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y mariadb105

    cat > /home/ec2-user/db_connection_info.txt <<EOT
    MySQL database connection information:

    Host: ${aws_lightsail_database.mysql.master_endpoint_address}
    Port: ${aws_lightsail_database.mysql.master_endpoint_port}
    Database: ${var.master_database_name}
    Username: ${var.master_username}

    Example connection command:
    mysql -h ${aws_lightsail_database.mysql.master_endpoint_address} -P ${aws_lightsail_database.mysql.master_endpoint_port} -u ${var.master_username} -p ${var.master_database_name}
    EOT

    chown ec2-user:ec2-user /home/ec2-user/db_connection_info.txt
    chmod 600 /home/ec2-user/db_connection_info.txt
  EOF

  tags = {
    Name        = var.instance_name
    Environment = "dev"
    ManagedBy   = "terraform"
  }

  depends_on = [
    aws_lightsail_database.mysql
  ]
}

resource "aws_lightsail_instance_public_ports" "app_ports" {
  instance_name = aws_lightsail_instance.app.name

  port_info {
    protocol  = "tcp"
    from_port = 22
    to_port   = 22
  }
}

output "lightsail_instance_name" {
  description = "Name of the Lightsail instance."
  value       = aws_lightsail_instance.app.name
}

output "lightsail_instance_public_ip" {
  description = "Public IP address of the Lightsail instance."
  value       = aws_lightsail_instance.app.public_ip_address
}

output "mysql_database_name" {
  description = "Name of the Lightsail MySQL database resource."
  value       = aws_lightsail_database.mysql.relational_database_name
}

output "mysql_database_endpoint" {
  description = "Endpoint address of the Lightsail MySQL database."
  value       = aws_lightsail_database.mysql.master_endpoint_address
}

output "mysql_database_port" {
  description = "Port of the Lightsail MySQL database."
  value       = aws_lightsail_database.mysql.master_endpoint_port
}

output "mysql_initial_database" {
  description = "Initial MySQL database created by Lightsail."
  value       = var.master_database_name
}

output "mysql_username" {
  description = "MySQL master username."
  value       = var.master_username
}
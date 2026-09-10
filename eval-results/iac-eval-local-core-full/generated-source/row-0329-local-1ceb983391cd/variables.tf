variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the benchmark VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private database subnets."
  type        = list(string)
  default     = ["10.0.101.0/24", "10.0.102.0/24"]
}

variable "db_instance_class" {
  description = "Instance class for the MySQL RDS instance."
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "benchmarkdb"
}

variable "db_username" {
  description = "Master username for the MySQL RDS instance."
  type        = string
  default     = "adminuser"
}

variable "db_password" {
  description = "Master password for the MySQL RDS instance. Benchmark-only default is not for production; override via tfvars or TF_VAR_db_password."
  type        = string
  sensitive   = true
  default     = "BenchmarkOnlyPassw0rd!"

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "db_password must be at least 8 characters."
  }
}

variable "aws_region" {
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix used for resource names."
  type        = string
  default     = "iac-eval-aurora"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Two availability zones for database subnets."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Exactly two availability zones must be provided."
  }
}

variable "database_subnet_cidr_blocks" {
  description = "CIDR blocks for the two database subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.database_subnet_cidr_blocks) == 2
    error_message = "Exactly two database subnet CIDR blocks must be provided."
  }
}

variable "client_cidr_blocks" {
  description = "CIDR blocks allowed to connect to the RDS cluster and proxy on MySQL port 3306."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "database_name" {
  description = "Initial Aurora MySQL database name."
  type        = string
  default     = "appdb"
}

variable "db_master_username" {
  description = "Master username for the Aurora MySQL cluster."
  type        = string
  sensitive   = true
}

variable "db_master_password" {
  description = "Master password for the Aurora MySQL cluster."
  type        = string
  sensitive   = true
}

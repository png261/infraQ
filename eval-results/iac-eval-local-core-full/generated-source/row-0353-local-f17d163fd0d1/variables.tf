variable "name_prefix" {
  description = "Prefix used for named resources."
  type        = string
  default     = "eval-aurora"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "Map of availability zones to private subnet CIDR blocks. Must contain at least two AZs for Aurora and RDS Proxy."
  type        = map(string)
  default = {
    "us-east-1a" = "10.0.1.0/24"
    "us-east-1b" = "10.0.2.0/24"
  }

  validation {
    condition     = length(var.private_subnet_cidrs) >= 2
    error_message = "private_subnet_cidrs must include at least two availability zones."
  }
}

variable "database_name" {
  description = "Initial Aurora MySQL database name."
  type        = string
  default     = "appdb"
}

variable "master_username" {
  description = "Aurora MySQL master username."
  type        = string
  sensitive   = true
}

variable "master_password" {
  description = "Aurora MySQL master password."
  type        = string
  sensitive   = true
}

variable "aurora_mysql_engine_version" {
  description = "Aurora MySQL engine version."
  type        = string
  default     = "8.0.mysql_aurora.3.05.2"
}

variable "aurora_instance_class" {
  description = "Instance class for the Aurora MySQL cluster instance."
  type        = string
  default     = "db.t4g.medium"
}

variable "backup_retention_period" {
  description = "Number of days to retain Aurora backups."
  type        = number
  default     = 1
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Two availability zones for the database subnets in us-east-1."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]

  validation {
    condition     = length(var.availability_zones) == 2
    error_message = "Exactly two availability zones must be provided."
  }
}

variable "cluster_identifier" {
  description = "Identifier for the Aurora MySQL cluster."
  type        = string
  default     = "aurora-mysql-cluster"
}

variable "aurora_mysql_engine_version" {
  description = "Aurora MySQL engine version."
  type        = string
  default     = "8.0.mysql_aurora.3.05.2"
}

variable "database_name" {
  description = "Initial database name."
  type        = string
  default     = "appdb"
}

variable "master_username" {
  description = "Master username for the Aurora MySQL cluster."
  type        = string
  sensitive   = true
}

variable "master_password" {
  description = "Master password for the Aurora MySQL cluster and RDS Proxy secret."
  type        = string
  sensitive   = true
}

variable "db_instance_class" {
  description = "Instance class for the Aurora MySQL cluster instance."
  type        = string
  default     = "db.t3.medium"
}

variable "secret_name" {
  description = "Name of the Secrets Manager secret that stores DB credentials."
  type        = string
  default     = "aurora-mysql-proxy-credentials"
}

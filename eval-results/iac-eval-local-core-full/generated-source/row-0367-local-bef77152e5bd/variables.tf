variable "relational_database_name" {
  description = "Name of the Lightsail relational database instance."
  type        = string
  default     = "benchmark-mysql-db"
}

variable "availability_zone" {
  description = "Availability Zone for the Lightsail database in us-east-1."
  type        = string
  default     = "us-east-1a"
}

variable "master_database_name" {
  description = "Name of the initial MySQL database to create."
  type        = string
  default     = "appdb"
}

variable "master_username" {
  description = "Master username for the Lightsail MySQL database."
  type        = string
  default     = "adminuser"
}

variable "master_password" {
  description = "Non-production benchmark placeholder master password for the Lightsail MySQL database. Stored in Terraform/OpenTofu state by the AWS provider; override for any real deployment."
  type        = string
  sensitive   = true
  default     = "BenchmarkMysqlPassw0rd!"
}

variable "bundle_id" {
  description = "Lightsail database bundle ID."
  type        = string
  default     = "micro_2_0"
}

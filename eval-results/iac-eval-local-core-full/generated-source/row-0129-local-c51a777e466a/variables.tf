variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public web subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_app_subnet_cidr" {
  description = "CIDR block for the private application subnet."
  type        = string
  default     = "10.0.2.0/24"
}

variable "private_db_subnet_cidr" {
  description = "CIDR block for the private database subnet."
  type        = string
  default     = "10.0.3.0/24"
}

variable "instance_type" {
  description = "EC2 instance type for web and application servers."
  type        = string
  default     = "t3.micro"
}

variable "app_port" {
  description = "TCP port exposed by the application server to the web tier."
  type        = number
  default     = 8080
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "RDS master username."
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "RDS master password. Supply with TF_VAR_db_password or a tfvars file that is not committed."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.db_password) >= 8
    error_message = "The db_password value must be at least 8 characters long."
  }
}

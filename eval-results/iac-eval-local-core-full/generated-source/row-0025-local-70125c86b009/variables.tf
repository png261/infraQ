variable "domain_name" {
  description = "Domain name to manage in Route 53."
  type        = string
  default     = "example.com"
}

variable "db_username" {
  description = "RDS master username for both regional databases."
  type        = string
  default     = "dbadmin"
  sensitive   = true
}

variable "db_password" {
  description = "RDS master password for both regional databases. Must be provided by the caller."
  type        = string
  sensitive   = true
}

variable "eb_service_role_name" {
  description = "Optional name of an existing Elastic Beanstalk service role to attach to both environments. Leave null to omit the ServiceRole setting."
  type        = string
  default     = null
}

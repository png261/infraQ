variable "db_username" {
  description = "Master username for the Airbyte connector test PostgreSQL database."
  type        = string
  default     = "airbyte"
}

variable "db_password" {
  description = "Master password for the Airbyte connector test PostgreSQL database. Provide a non-default value for real deployments."
  type        = string
  sensitive   = true
  default     = "AirbyteTestPassword123!"
}

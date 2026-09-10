variable "master_password" {
  description = "Master password for the Lightsail PostgreSQL database. Must satisfy AWS Lightsail password requirements."
  type        = string
  sensitive   = true
}

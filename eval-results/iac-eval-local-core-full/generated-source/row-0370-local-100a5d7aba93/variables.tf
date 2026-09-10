variable "master_password" {
  description = "Master password for the Lightsail PostgreSQL database. This value is sensitive and will be stored in Terraform state."
  type        = string
  sensitive   = true
}

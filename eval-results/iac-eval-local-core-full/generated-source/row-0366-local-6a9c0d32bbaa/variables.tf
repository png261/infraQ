variable "master_password" {
  description = "Master password for the Lightsail managed database. This value is sensitive but will still be stored in Terraform/OpenTofu state by the AWS provider."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.master_password) >= 8
    error_message = "The master_password value must be at least 8 characters long."
  }
}

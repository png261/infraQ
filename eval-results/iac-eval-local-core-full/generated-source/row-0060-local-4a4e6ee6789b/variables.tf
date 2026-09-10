variable "redshift_master_password" {
  description = "Master password for the benchmark Redshift cluster and Firehose COPY connection. Provide with TF_VAR_redshift_master_password or a tfvars file; it is sensitive and will be stored in Terraform state by the AWS provider."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.redshift_master_password) >= 8
    error_message = "The Redshift master password must be at least 8 characters long."
  }
}

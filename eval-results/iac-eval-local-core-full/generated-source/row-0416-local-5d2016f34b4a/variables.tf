variable "db_username" {
  description = "Master username for the restored RDS database."
  type        = string
  default     = "adminuser"
}

variable "db_password" {
  description = "Master password for the restored RDS database. Provide a real value at plan/apply time."
  type        = string
  sensitive   = true
}

variable "s3_import_bucket_name" {
  description = "Name of the S3 bucket containing the source database backup files."
  type        = string
  default     = "example-rds-import-bucket"
}

variable "s3_import_role_arn" {
  description = "ARN of the IAM role that permits RDS to read the S3 import bucket."
  type        = string
  default     = "arn:aws:iam::123456789012:role/rds-s3-import-role"
}

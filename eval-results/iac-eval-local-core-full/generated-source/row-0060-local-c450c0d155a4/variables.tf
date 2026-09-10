variable "redshift_master_username" {
  description = "Master username for the Redshift cluster and Firehose Redshift destination connection."
  type        = string
  default     = "firehose_admin"
}

variable "redshift_master_password" {
  description = "Master password for the Redshift cluster and Firehose Redshift destination connection."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.redshift_master_password) >= 8
    error_message = "The Redshift master password must be at least 8 characters long."
  }
}

variable "redshift_database_name" {
  description = "Name of the initial Redshift database."
  type        = string
  default     = "firehosedb"
}

variable "redshift_table_name" {
  description = "Existing Redshift table that Firehose will COPY records into."
  type        = string
  default     = "firehose_events"
}

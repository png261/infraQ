variable "snapshot_identifier" {
  description = "Identifier or ARN of the DB snapshot to restore from."
  type        = string
  default     = "benchmark-db-snapshot"
}

variable "db_username" {
  description = "Master username for the restored database instance."
  type        = string
  default     = "benchmarkadmin"
}

variable "db_password" {
  description = "Master password for the restored database instance. Required by the benchmark; this value is stored in Terraform/OpenTofu state."
  type        = string
  sensitive   = true
  default     = "BenchmarkPassword123!"
}

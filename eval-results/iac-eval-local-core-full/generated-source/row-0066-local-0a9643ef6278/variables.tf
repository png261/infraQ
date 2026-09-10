variable "bucket_name" {
  description = "Optional name for the S3 backup bucket. Leave null to let AWS generate a unique name from bucket_prefix."
  type        = string
  default     = null
}

variable "bucket_prefix" {
  description = "Prefix used when bucket_name is null."
  type        = string
  default     = "firehose-http-backup-"
}

variable "firehose_stream_name" {
  description = "Name of the Kinesis Data Firehose delivery stream."
  type        = string
  default     = "http-endpoint-delivery-stream"
}

variable "http_endpoint_name" {
  description = "Display name for the HTTP endpoint destination, such as New Relic."
  type        = string
  default     = "New Relic"
}

variable "http_endpoint_url" {
  description = "HTTP endpoint URL that receives Firehose records."
  type        = string
  default     = "https://example.com/firehose"
}

variable "http_endpoint_access_key" {
  description = "Access key or license key for the HTTP endpoint destination. This value is sensitive and is not hard-coded."
  type        = string
  sensitive   = true
}

variable "s3_backup_prefix" {
  description = "S3 prefix for failed or all delivery records backed up from Firehose."
  type        = string
  default     = "firehose-backup/"
}

variable "force_destroy_backup_bucket" {
  description = "Whether to allow Terraform/OpenTofu to delete the backup bucket even when it contains objects."
  type        = bool
  default     = false
}

variable "backup_bucket_name" {
  description = "Globally unique S3 bucket name used by Firehose to back up failed Splunk delivery events."
  type        = string
}

variable "delivery_stream_name" {
  description = "Name of the Kinesis Data Firehose delivery stream."
  type        = string
  default     = "dev-splunk-firehose"
}

variable "firehose_role_name" {
  description = "Name of the IAM role assumed by Kinesis Data Firehose."
  type        = string
  default     = "dev-splunk-firehose-role"
}

variable "splunk_hec_endpoint" {
  description = "Splunk HTTP Event Collector endpoint URL, for example https://http-inputs.example.splunkcloud.com:443."
  type        = string
}

variable "splunk_hec_endpoint_type" {
  description = "Splunk HEC endpoint type. Valid values are Raw or Event."
  type        = string
  default     = "Event"

  validation {
    condition     = contains(["Raw", "Event"], var.splunk_hec_endpoint_type)
    error_message = "splunk_hec_endpoint_type must be either Raw or Event."
  }
}

variable "splunk_hec_token" {
  description = "Splunk HTTP Event Collector token. This value is sensitive, but will still be stored in Terraform/OpenTofu state if deployed."
  type        = string
  sensitive   = true
}

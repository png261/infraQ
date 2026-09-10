variable "name_prefix" {
  description = "Prefix used for named resources."
  type        = string
  default     = "iac-eval-msk"
}

variable "kafka_version" {
  description = "Kafka version for the MSK cluster."
  type        = string
  default     = "3.6.0"
}

variable "broker_instance_type" {
  description = "Instance type for MSK broker nodes."
  type        = string
  default     = "kafka.t3.small"
}

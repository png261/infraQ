variable "aws_region" {
  description = "AWS region for the drift detection demonstration resources."
  type        = string
  default     = "ap-southeast-1"
}

variable "test_id" {
  description = "Unique suffix for demonstration resources."
  type        = string
  default     = "demo"
}

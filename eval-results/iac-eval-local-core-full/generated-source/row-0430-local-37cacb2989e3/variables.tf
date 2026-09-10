variable "name" {
  description = "Name tag value for all resources."
  type        = string
  default     = "dedicated-vpc"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the dedicated-tenancy VPC."
  type        = string
  default     = "10.0.0.0/16"
}

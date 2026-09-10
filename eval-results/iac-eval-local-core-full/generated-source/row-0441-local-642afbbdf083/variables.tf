variable "name" {
  description = "Name prefix used for the VPC and egress-only internet gateway resources."
  type        = string
  default     = "ipv6-egress-only"
}

variable "vpc_cidr_block" {
  description = "IPv4 CIDR block for the VPC. IPv6 is assigned by AWS for egress-only internet access."
  type        = string
  default     = "10.0.0.0/16"
}

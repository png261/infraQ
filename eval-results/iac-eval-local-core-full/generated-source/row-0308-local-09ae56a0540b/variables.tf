variable "public_key" {
  description = "Public key material for the EC2 key pair used by the benchmark instance."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the benchmark instance."
  type        = string
  default     = "t3.micro"
}

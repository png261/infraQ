variable "project_name" {
  description = "Name prefix used for resource naming and tags."
  type        = string
  default     = "efs-private-linux"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet that hosts the NAT gateway."
  type        = string
  default     = "10.0.0.0/24"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for the two private subnets."
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.private_subnet_cidrs) == 2
    error_message = "Exactly two private subnet CIDR blocks are required."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the Amazon Linux instances."
  type        = string
  default     = "t3.micro"
}

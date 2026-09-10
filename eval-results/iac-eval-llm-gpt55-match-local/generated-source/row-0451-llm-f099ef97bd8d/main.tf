terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the NAT Gateway will be created."
  type        = string
  default     = "us-east-1"
}

variable "subnet_id" {
  description = "The ID of the public subnet where the NAT Gateway will be created."
  type        = string
  default     = "subnet-0123456789abcdef0"
}

variable "elastic_ip_allocation_id" {
  description = "The allocation ID of the Elastic IP address to associate with the NAT Gateway."
  type        = string
  default     = "eipalloc-0123456789abcdef0"
}

variable "nat_gateway_name" {
  description = "Name tag for the NAT Gateway."
  type        = string
  default     = "public-nat-gateway"
}

resource "aws_nat_gateway" "public_nat_gateway" {
  subnet_id         = var.subnet_id
  allocation_id    = var.elastic_ip_allocation_id
  connectivity_type = "public"

  tags = {
    Name = var.nat_gateway_name
  }
}

output "nat_gateway_id" {
  description = "The ID of the created NAT Gateway."
  value       = aws_nat_gateway.public_nat_gateway.id
}

output "nat_gateway_public_ip" {
  description = "The public IP address associated with the NAT Gateway."
  value       = aws_nat_gateway.public_nat_gateway.public_ip
}

output "nat_gateway_subnet_id" {
  description = "The subnet ID where the NAT Gateway was created."
  value       = aws_nat_gateway.public_nat_gateway.subnet_id
}
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
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "vpc_id" {
  description = "Existing VPC ID to associate with the DHCP options. Leave empty to create a new VPC."
  type        = string
  default     = ""
}

variable "vpc_cidr_block" {
  description = "CIDR block for the default VPC created when var.vpc_id is empty."
  type        = string
  default     = "10.0.0.0/16"
}

resource "aws_vpc" "pike" {
  count = var.vpc_id == "" ? 1 : 0

  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "pike"
    permissions = "permissions"
  }
}

locals {
  target_vpc_id = var.vpc_id == "" ? aws_vpc.pike[0].id : var.vpc_id
}

resource "aws_vpc_dhcp_options" "pike" {
  domain_name_servers = [
    "8.8.8.8",
    "8.8.4.4"
  ]

  tags = {
    Name        = "pike"
    permissions = "permissions"
  }
}

resource "aws_vpc_dhcp_options_association" "pike" {
  vpc_id          = local.target_vpc_id
  dhcp_options_id = aws_vpc_dhcp_options.pike.id
}

output "dhcp_options_id" {
  description = "ID of the created DHCP options set."
  value       = aws_vpc_dhcp_options.pike.id
}

output "associated_vpc_id" {
  description = "VPC ID associated with the DHCP options."
  value       = local.target_vpc_id
}
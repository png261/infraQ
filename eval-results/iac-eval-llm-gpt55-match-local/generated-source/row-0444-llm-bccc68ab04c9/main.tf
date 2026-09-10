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
  description = "CIDR block for the VPC created when vpc_id is not provided."
  type        = string
  default     = "10.0.0.0/16"
}

resource "aws_vpc" "default" {
  count = var.vpc_id == "" ? 1 : 0

  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "pike-vpc"
  }
}

resource "aws_vpc_dhcp_options" "pike" {
  domain_name_servers = [
    "8.8.8.8",
    "8.8.4.4"
  ]

  tags = {
    Name = "pike"
  }
}

resource "aws_vpc_dhcp_options_association" "pike" {
  vpc_id = var.vpc_id != "" ? var.vpc_id : aws_vpc.default[0].id

  dhcp_options_id = aws_vpc_dhcp_options.pike.id
}

output "dhcp_options_id" {
  description = "ID of the DHCP options set named pike."
  value       = aws_vpc_dhcp_options.pike.id
}

output "associated_vpc_id" {
  description = "VPC ID associated with the DHCP options."
  value       = aws_vpc_dhcp_options_association.pike.vpc_id
}
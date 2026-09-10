terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the VPC and DHCP options set will be created."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "192.168.0.0/16"
}

variable "dhcp_domain_name" {
  description = "Domain name to assign through DHCP options."
  type        = string
  default     = "windomain.local"
}

variable "dhcp_domain_name_servers" {
  description = "List of DNS servers to assign through DHCP options."
  type        = list(string)
  default     = ["192.168.56.102", "8.8.8.8"]
}

variable "dhcp_netbios_name_servers" {
  description = "List of NetBIOS name servers to assign through DHCP options."
  type        = list(string)
  default     = ["192.168.56.102"]
}

variable "dhcp_netbios_node_type" {
  description = "NetBIOS node type. 2 indicates P-node."
  type        = number
  default     = 2
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "custom-dhcp-vpc"
  }
}

resource "aws_vpc_dhcp_options" "custom" {
  domain_name          = var.dhcp_domain_name
  domain_name_servers  = var.dhcp_domain_name_servers
  netbios_name_servers = var.dhcp_netbios_name_servers
  netbios_node_type    = var.dhcp_netbios_node_type

  tags = {
    Name = "custom-dhcp-options"
  }
}

resource "aws_vpc_dhcp_options_association" "main" {
  vpc_id          = aws_vpc.main.id
  dhcp_options_id = aws_vpc_dhcp_options.custom.id
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the created VPC."
  value       = aws_vpc.main.cidr_block
}

output "dhcp_options_id" {
  description = "ID of the custom DHCP options set."
  value       = aws_vpc_dhcp_options.custom.id
}
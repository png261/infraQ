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
  description = "AWS region where the VPCs and peering connection will be created."
  type        = string
  default     = "us-east-1"
}

variable "peer_vpc_cidr" {
  description = "CIDR block for the peer VPC."
  type        = string
  default     = "10.10.0.0/16"
}

variable "base_vpc_cidr" {
  description = "CIDR block for the base VPC."
  type        = string
  default     = "10.20.0.0/16"
}

resource "aws_vpc" "peer" {
  cidr_block           = var.peer_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "peer"
  }
}

resource "aws_vpc" "base" {
  cidr_block           = var.base_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "base"
  }
}

resource "aws_vpc_peering_connection" "pike" {
  vpc_id      = aws_vpc.peer.id
  peer_vpc_id = aws_vpc.base.id
  auto_accept = true

  tags = {
    Name = "pike"
    pike = "permissions"
  }
}

resource "aws_route" "peer_to_base" {
  route_table_id            = aws_vpc.peer.default_route_table_id
  destination_cidr_block    = aws_vpc.base.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.pike.id

  depends_on = [
    aws_vpc_peering_connection.pike
  ]
}

resource "aws_route" "base_to_peer" {
  route_table_id            = aws_vpc.base.default_route_table_id
  destination_cidr_block    = aws_vpc.peer.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.pike.id

  depends_on = [
    aws_vpc_peering_connection.pike
  ]
}

output "peer_vpc_id" {
  description = "ID of the peer VPC."
  value       = aws_vpc.peer.id
}

output "base_vpc_id" {
  description = "ID of the base VPC."
  value       = aws_vpc.base.id
}

output "vpc_peering_connection_id" {
  description = "ID of the pike VPC peering connection."
  value       = aws_vpc_peering_connection.pike.id
}
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
  description = "AWS region where the VPCs and VPC peering connection will be created."
  type        = string
  default     = "us-east-1"
}

variable "peer_vpc_cidr" {
  description = "CIDR block for the peer VPC."
  type        = string
  default     = "10.0.0.0/24"
}

variable "base_vpc_cidr" {
  description = "CIDR block for the base VPC."
  type        = string
  default     = "10.1.0.0/24"
}

variable "peer_subnet_cidr" {
  description = "CIDR block for the subnet in the peer VPC."
  type        = string
  default     = "10.0.0.0/25"
}

variable "base_subnet_cidr" {
  description = "CIDR block for the subnet in the base VPC."
  type        = string
  default     = "10.1.0.0/25"
}

data "aws_availability_zones" "available" {
  state = "available"
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

resource "aws_subnet" "peer" {
  vpc_id            = aws_vpc.peer.id
  cidr_block        = var.peer_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "peer-subnet"
  }
}

resource "aws_subnet" "base" {
  vpc_id            = aws_vpc.base.id
  cidr_block        = var.base_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "base-subnet"
  }
}

resource "aws_vpc_peering_connection" "pike" {
  vpc_id      = aws_vpc.peer.id
  peer_vpc_id = aws_vpc.base.id
  auto_accept = true

  tags = {
    Name = "pike"
  }
}

resource "aws_route_table" "peer" {
  vpc_id = aws_vpc.peer.id

  tags = {
    Name = "peer-route-table"
  }
}

resource "aws_route_table" "base" {
  vpc_id = aws_vpc.base.id

  tags = {
    Name = "base-route-table"
  }
}

resource "aws_route" "peer_to_base" {
  route_table_id            = aws_route_table.peer.id
  destination_cidr_block    = aws_vpc.base.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.pike.id
}

resource "aws_route" "base_to_peer" {
  route_table_id            = aws_route_table.base.id
  destination_cidr_block    = aws_vpc.peer.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.pike.id
}

resource "aws_route_table_association" "peer" {
  subnet_id      = aws_subnet.peer.id
  route_table_id = aws_route_table.peer.id
}

resource "aws_route_table_association" "base" {
  subnet_id      = aws_subnet.base.id
  route_table_id = aws_route_table.base.id
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
  description = "ID of the VPC peering connection named pike."
  value       = aws_vpc_peering_connection.pike.id
}
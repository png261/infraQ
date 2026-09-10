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
  description = "AWS region where the VPCs will be created"
  type        = string
  default     = "us-east-1"
}

variable "vpc_a_cidr" {
  description = "CIDR block for VPC A"
  type        = string
  default     = "10.10.0.0/16"
}

variable "vpc_b_cidr" {
  description = "CIDR block for VPC B"
  type        = string
  default     = "10.20.0.0/16"
}

variable "vpc_a_subnet_cidr" {
  description = "CIDR block for subnet in VPC A"
  type        = string
  default     = "10.10.1.0/24"
}

variable "vpc_b_subnet_cidr" {
  description = "CIDR block for subnet in VPC B"
  type        = string
  default     = "10.20.1.0/24"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_vpc" "vpc_a" {
  cidr_block           = var.vpc_a_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "terraform-vpc-a"
  }
}

resource "aws_vpc" "vpc_b" {
  cidr_block           = var.vpc_b_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "terraform-vpc-b"
  }
}

resource "aws_subnet" "vpc_a_subnet" {
  vpc_id                  = aws_vpc.vpc_a.id
  cidr_block              = var.vpc_a_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "terraform-vpc-a-subnet"
  }
}

resource "aws_subnet" "vpc_b_subnet" {
  vpc_id                  = aws_vpc.vpc_b.id
  cidr_block              = var.vpc_b_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "terraform-vpc-b-subnet"
  }
}

resource "aws_vpc_peering_connection" "vpc_a_to_vpc_b" {
  vpc_id      = aws_vpc.vpc_a.id
  peer_vpc_id = aws_vpc.vpc_b.id
  auto_accept = true

  tags = {
    Name = "terraform-vpc-a-to-vpc-b-peering"
  }
}

resource "aws_vpc_peering_connection_options" "vpc_a_to_vpc_b_options" {
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_a_to_vpc_b.id

  requester {
    allow_remote_vpc_dns_resolution = true
  }

  accepter {
    allow_remote_vpc_dns_resolution = true
  }
}

resource "aws_route_table" "vpc_a_route_table" {
  vpc_id = aws_vpc.vpc_a.id

  tags = {
    Name = "terraform-vpc-a-route-table"
  }
}

resource "aws_route_table" "vpc_b_route_table" {
  vpc_id = aws_vpc.vpc_b.id

  tags = {
    Name = "terraform-vpc-b-route-table"
  }
}

resource "aws_route" "vpc_a_to_vpc_b" {
  route_table_id            = aws_route_table.vpc_a_route_table.id
  destination_cidr_block    = aws_vpc.vpc_b.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_a_to_vpc_b.id

  depends_on = [
    aws_vpc_peering_connection.vpc_a_to_vpc_b
  ]
}

resource "aws_route" "vpc_b_to_vpc_a" {
  route_table_id            = aws_route_table.vpc_b_route_table.id
  destination_cidr_block    = aws_vpc.vpc_a.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.vpc_a_to_vpc_b.id

  depends_on = [
    aws_vpc_peering_connection.vpc_a_to_vpc_b
  ]
}

resource "aws_route_table_association" "vpc_a_subnet_association" {
  subnet_id      = aws_subnet.vpc_a_subnet.id
  route_table_id = aws_route_table.vpc_a_route_table.id
}

resource "aws_route_table_association" "vpc_b_subnet_association" {
  subnet_id      = aws_subnet.vpc_b_subnet.id
  route_table_id = aws_route_table.vpc_b_route_table.id
}

output "vpc_a_id" {
  description = "ID of VPC A"
  value       = aws_vpc.vpc_a.id
}

output "vpc_b_id" {
  description = "ID of VPC B"
  value       = aws_vpc.vpc_b.id
}

output "vpc_peering_connection_id" {
  description = "ID of the VPC peering connection"
  value       = aws_vpc_peering_connection.vpc_a_to_vpc_b.id
}
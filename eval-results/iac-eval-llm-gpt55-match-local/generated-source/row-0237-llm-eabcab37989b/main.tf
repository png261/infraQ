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
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr_block" {
  description = "CIDR block for the subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to access SSH."
  type        = string
  default     = "0.0.0.0/0"
}

variable "allowed_http_cidr" {
  description = "CIDR block allowed to access HTTP."
  type        = string
  default     = "0.0.0.0/0"
}

variable "allowed_https_cidr" {
  description = "CIDR block allowed to access HTTPS."
  type        = string
  default     = "0.0.0.0/0"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "example-vpc"
  }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr_block
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true

  tags = {
    Name = "example-subnet"
  }
}

resource "aws_network_acl" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "example-network-acl"
  }
}

resource "aws_network_acl_association" "main" {
  subnet_id      = aws_subnet.main.id
  network_acl_id = aws_network_acl.main.id
}

resource "aws_network_acl_rule" "allow_ingress_ssh" {
  network_acl_id = aws_network_acl.main.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.allowed_ssh_cidr
  from_port      = 22
  to_port        = 22
}

resource "aws_network_acl_rule" "allow_ingress_http" {
  network_acl_id = aws_network_acl.main.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.allowed_http_cidr
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "allow_ingress_https" {
  network_acl_id = aws_network_acl.main.id
  rule_number    = 120
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.allowed_https_cidr
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "allow_ingress_ephemeral" {
  network_acl_id = aws_network_acl.main.id
  rule_number    = 130
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

resource "aws_network_acl_rule" "allow_egress_http" {
  network_acl_id = aws_network_acl.main.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "allow_egress_https" {
  network_acl_id = aws_network_acl.main.id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "allow_egress_ephemeral" {
  network_acl_id = aws_network_acl.main.id
  rule_number    = 120
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 1024
  to_port        = 65535
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "subnet_id" {
  description = "ID of the created subnet."
  value       = aws_subnet.main.id
}

output "network_acl_id" {
  description = "ID of the created Network ACL."
  value       = aws_network_acl.main.id
}
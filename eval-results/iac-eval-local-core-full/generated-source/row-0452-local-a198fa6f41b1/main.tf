terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "peer" {
  cidr_block = "10.0.0.0/24"
}

resource "aws_vpc" "base" {
  cidr_block = "10.1.0.0/24"
}

resource "aws_vpc_peering_connection" "pike" {
  vpc_id      = aws_vpc.peer.id
  peer_vpc_id = aws_vpc.base.id
  auto_accept = true

  tags = {
    pike = "permissions"
  }
}

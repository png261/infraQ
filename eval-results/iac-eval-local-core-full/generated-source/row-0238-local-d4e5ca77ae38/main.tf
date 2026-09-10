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
  region = "us-east-1"
}

resource "aws_vpc" "requester" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "benchmark-requester-vpc"
  }
}

resource "aws_vpc" "peer" {
  cidr_block           = "10.1.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "benchmark-peer-vpc"
  }
}

resource "aws_vpc_peering_connection" "requester_to_peer" {
  vpc_id      = aws_vpc.requester.id
  peer_vpc_id = aws_vpc.peer.id
  auto_accept = true

  tags = {
    Name = "benchmark-vpc-peering"
  }
}

resource "aws_vpc" "redshift" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "redshift-endpoint-vpc"
  }
}

resource "aws_subnet" "redshift_a" {
  vpc_id            = aws_vpc.redshift.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "redshift-endpoint-subnet-a"
  }
}

resource "aws_subnet" "redshift_b" {
  vpc_id            = aws_vpc.redshift.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "redshift-endpoint-subnet-b"
  }
}

resource "aws_security_group" "redshift_endpoint" {
  name        = "redshift-endpoint-access-sg"
  description = "Security group for Redshift endpoint access"
  vpc_id      = aws_vpc.redshift.id

  tags = {
    Name = "redshift-endpoint-access-sg"
  }
}

resource "aws_redshift_subnet_group" "redshift" {
  name = "redshift-endpoint-subnet-group"
  subnet_ids = [
    aws_subnet.redshift_a.id,
    aws_subnet.redshift_b.id,
  ]

  tags = {
    Name = "redshift-endpoint-subnet-group"
  }
}

resource "aws_redshift_cluster" "redshift" {
  cluster_identifier        = "redshift-endpoint-cluster"
  database_name             = "dev"
  master_username           = "adminuser"
  master_password           = var.redshift_master_password
  node_type                 = "dc2.large"
  cluster_type              = "single-node"
  cluster_subnet_group_name = aws_redshift_subnet_group.redshift.name
  skip_final_snapshot       = true

  tags = {
    Name = "redshift-endpoint-cluster"
  }
}

resource "aws_redshift_endpoint_access" "redshift" {
  endpoint_name          = "redshift-endpoint-access"
  subnet_group_name      = aws_redshift_subnet_group.redshift.name
  cluster_identifier     = aws_redshift_cluster.redshift.cluster_identifier
  vpc_security_group_ids = [aws_security_group.redshift_endpoint.id]
}

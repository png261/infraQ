data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

resource "aws_vpc" "redshift" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "benchmark-redshift-vpc"
  }
}

resource "aws_subnet" "redshift" {
  count = 2

  vpc_id            = aws_vpc.redshift.id
  cidr_block        = cidrsubnet(aws_vpc.redshift.cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "benchmark-redshift-subnet-${count.index + 1}"
  }
}

resource "aws_redshift_subnet_group" "redshift" {
  name       = "benchmark-redshift-subnet-group"
  subnet_ids = aws_subnet.redshift[*].id

  tags = {
    Name = "benchmark-redshift-subnet-group"
  }
}

resource "aws_security_group" "redshift" {
  name        = "benchmark-redshift-sg"
  description = "Security group for benchmark Redshift cluster"
  vpc_id      = aws_vpc.redshift.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "benchmark-redshift-sg"
  }
}

resource "aws_redshift_cluster" "benchmark" {
  cluster_identifier        = "benchmark-redshift-cluster"
  database_name             = "benchmarkdb"
  master_username           = var.redshift_master_username
  master_password           = var.redshift_master_password
  node_type                 = "dc2.large"
  cluster_type              = "multi-node"
  number_of_nodes           = 2
  publicly_accessible       = false
  enhanced_vpc_routing      = true
  skip_final_snapshot       = true
  cluster_subnet_group_name = aws_redshift_subnet_group.redshift.name
  vpc_security_group_ids    = [aws_security_group.redshift.id]

  tags = {
    Name = "benchmark-redshift-cluster"
  }
}

resource "aws_redshift_endpoint_authorization" "benchmark" {
  account             = "012345678910"
  cluster_identifier  = aws_redshift_cluster.benchmark.cluster_identifier
  vpc_ids             = [aws_vpc.redshift.id]
  force_delete        = true
}

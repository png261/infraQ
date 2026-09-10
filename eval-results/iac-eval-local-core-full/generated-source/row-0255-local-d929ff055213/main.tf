resource "aws_vpc" "example" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "example-redshift-vpc"
  }
}

resource "aws_subnet" "example_a" {
  vpc_id            = aws_vpc.example.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "example-redshift-subnet-a"
  }
}

resource "aws_subnet" "example_b" {
  vpc_id            = aws_vpc.example.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "example-redshift-subnet-b"
  }
}

resource "aws_redshift_subnet_group" "example" {
  name       = "example-redshift-subnet-group"
  subnet_ids = [aws_subnet.example_a.id, aws_subnet.example_b.id]

  tags = {
    Name = "example-redshift-subnet-group"
  }
}

resource "aws_redshift_cluster" "example" {
  cluster_identifier        = "example-redshift-cluster"
  database_name             = "exampledb"
  master_username           = "exampleadmin"
  master_password           = var.redshift_master_password
  node_type                 = "dc2.large"
  cluster_type              = "single-node"
  cluster_subnet_group_name = aws_redshift_subnet_group.example.name
  publicly_accessible       = false
  skip_final_snapshot       = true
}

resource "aws_redshift_endpoint_access" "example" {
  endpoint_name      = "example-redshift-endpoint"
  cluster_identifier = aws_redshift_cluster.example.cluster_identifier
  subnet_group_name  = aws_redshift_subnet_group.example.name
}

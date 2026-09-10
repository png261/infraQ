resource "aws_vpc" "redshift" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "redshift-ha-vpc"
  }
}

resource "aws_internet_gateway" "redshift" {
  vpc_id = aws_vpc.redshift.id

  tags = {
    Name = "redshift-ha-igw"
  }
}

resource "aws_subnet" "redshift_a" {
  vpc_id            = aws_vpc.redshift.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "redshift-ha-subnet-a"
  }
}

resource "aws_subnet" "redshift_b" {
  vpc_id            = aws_vpc.redshift.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "redshift-ha-subnet-b"
  }
}

resource "aws_redshift_subnet_group" "redshift" {
  name       = "redshift-ha-subnet-group"
  subnet_ids = [aws_subnet.redshift_a.id, aws_subnet.redshift_b.id]

  tags = {
    Name = "redshift-ha-subnet-group"
  }
}

resource "aws_redshift_cluster" "redshift" {
  cluster_identifier        = "redshift-ha-cluster"
  database_name             = "dev"
  master_username           = var.redshift_admin_username
  master_password           = var.redshift_admin_password
  node_type                 = "dc2.large"
  cluster_type              = "multi-node"
  number_of_nodes           = 2
  cluster_subnet_group_name = aws_redshift_subnet_group.redshift.name
  publicly_accessible       = false
  skip_final_snapshot       = true

  tags = {
    Name = "redshift-ha-cluster"
  }
}

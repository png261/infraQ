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

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "redshift_cluster_resource_policy" {
  statement {
    sid    = "AllowAccountDescribeCluster"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions = [
      "redshift:DescribeClusters"
    ]

    resources = [aws_redshift_cluster.this.arn]
  }
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.cluster_identifier}-vpc"
  }
}

resource "aws_subnet" "redshift" {
  for_each = var.redshift_subnet_cidr_blocks

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = {
    Name = "${var.cluster_identifier}-${each.key}"
  }
}

resource "aws_security_group" "redshift" {
  name        = "${var.cluster_identifier}-sg"
  description = "Security group for the private Redshift cluster."
  vpc_id      = aws_vpc.this.id

  egress {
    description = "Allow all outbound traffic."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_identifier}-sg"
  }
}

resource "aws_redshift_subnet_group" "this" {
  name       = "${var.cluster_identifier}-subnet-group"
  subnet_ids = [for subnet in aws_subnet.redshift : subnet.id]

  tags = {
    Name = "${var.cluster_identifier}-subnet-group"
  }
}

resource "aws_redshift_cluster" "this" {
  cluster_identifier        = var.cluster_identifier
  database_name             = var.database_name
  master_username           = var.master_username
  master_password           = var.master_password
  node_type                 = var.node_type
  cluster_type              = "multi-node"
  number_of_nodes           = 2
  cluster_subnet_group_name = aws_redshift_subnet_group.this.name
  vpc_security_group_ids    = [aws_security_group.redshift.id]

  encrypted           = true
  publicly_accessible = false
  skip_final_snapshot = true
}

resource "aws_redshift_resource_policy" "this" {
  resource_arn = aws_redshift_cluster.this.arn
  policy       = data.aws_iam_policy_document.redshift_cluster_resource_policy.json
}

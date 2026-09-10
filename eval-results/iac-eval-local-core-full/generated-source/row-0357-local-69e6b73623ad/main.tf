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

locals {
  db_credentials = {
    username = var.master_username
    password = var.master_password
  }
}

data "aws_iam_policy_document" "rds_proxy_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "rds_proxy_secret_access" {
  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [aws_secretsmanager_secret.db_credentials.arn]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "aurora-proxy-vpc"
  }
}

resource "aws_subnet" "database" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone = var.availability_zones[count.index]

  tags = {
    Name = "aurora-proxy-db-${count.index + 1}"
  }
}

resource "aws_security_group" "database" {
  name        = "aurora-proxy-database-sg"
  description = "Allow MySQL traffic between EC2 clients, RDS Proxy, and Aurora"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "MySQL from resources using this security group"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "aurora-proxy-database-sg"
  }
}

resource "aws_db_subnet_group" "database" {
  name       = "aurora-proxy-db-subnet-group"
  subnet_ids = aws_subnet.database[*].id

  tags = {
    Name = "aurora-proxy-db-subnet-group"
  }
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name = var.secret_name

  tags = {
    Name = var.secret_name
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id     = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode(local.db_credentials)
}

resource "aws_iam_role" "rds_proxy" {
  name               = "aurora-mysql-rds-proxy-role"
  assume_role_policy = data.aws_iam_policy_document.rds_proxy_assume_role.json

  tags = {
    Name = "aurora-mysql-rds-proxy-role"
  }
}

resource "aws_iam_role_policy" "rds_proxy_secret_access" {
  name   = "aurora-mysql-rds-proxy-secret-access"
  role   = aws_iam_role.rds_proxy.id
  policy = data.aws_iam_policy_document.rds_proxy_secret_access.json
}

resource "aws_rds_cluster" "aurora_mysql" {
  cluster_identifier        = var.cluster_identifier
  engine                    = "aurora-mysql"
  engine_version            = var.aurora_mysql_engine_version
  database_name             = var.database_name
  master_username           = var.master_username
  master_password           = var.master_password
  db_subnet_group_name      = aws_db_subnet_group.database.name
  vpc_security_group_ids    = [aws_security_group.database.id]
  skip_final_snapshot       = false
  final_snapshot_identifier = "snapshot"

  tags = {
    Name = var.cluster_identifier
  }
}

resource "aws_rds_cluster_instance" "aurora_mysql" {
  identifier           = "${var.cluster_identifier}-instance-1"
  cluster_identifier   = aws_rds_cluster.aurora_mysql.id
  instance_class       = var.db_instance_class
  engine               = aws_rds_cluster.aurora_mysql.engine
  engine_version       = aws_rds_cluster.aurora_mysql.engine_version
  db_subnet_group_name = aws_db_subnet_group.database.name

  tags = {
    Name = "${var.cluster_identifier}-instance-1"
  }
}

resource "aws_db_proxy" "mysql" {
  name                   = "aurora-mysql-proxy"
  engine_family          = "MYSQL"
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_subnet_ids         = aws_subnet.database[*].id
  vpc_security_group_ids = [aws_security_group.database.id]
  require_tls            = true

  auth {
    auth_scheme = "SECRETS"
    secret_arn  = aws_secretsmanager_secret.db_credentials.arn
    iam_auth    = "DISABLED"
  }

  tags = {
    Name = "aurora-mysql-proxy"
  }

  depends_on = [
    aws_iam_role_policy.rds_proxy_secret_access,
    aws_secretsmanager_secret_version.db_credentials
  ]
}

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

locals {
  name_prefix = var.name_prefix
  db_name     = replace(var.database_name, "-", "_")
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_subnet" "private" {
  for_each = var.private_subnet_cidrs

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = {
    Name = "${local.name_prefix}-private-${each.key}"
  }
}

resource "aws_security_group" "database" {
  name        = "${local.name_prefix}-rds-proxy-sg"
  description = "Allow MySQL traffic between EC2 clients, RDS Proxy, and Aurora cluster"
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
    Name = "${local.name_prefix}-rds-proxy-sg"
  }
}

resource "aws_db_subnet_group" "aurora" {
  name       = "${local.name_prefix}-aurora-subnets"
  subnet_ids = [for subnet in aws_subnet.private : subnet.id]

  tags = {
    Name = "${local.name_prefix}-aurora-subnets"
  }
}

resource "aws_rds_cluster" "aurora_mysql" {
  cluster_identifier      = "${local.name_prefix}-aurora-mysql"
  engine                  = "aurora-mysql"
  engine_version          = var.aurora_mysql_engine_version
  database_name           = local.db_name
  master_username         = var.master_username
  master_password         = var.master_password
  db_subnet_group_name    = aws_db_subnet_group.aurora.name
  vpc_security_group_ids  = [aws_security_group.database.id]
  backup_retention_period = var.backup_retention_period
  skip_final_snapshot     = true

  tags = {
    Name = "${local.name_prefix}-aurora-mysql"
  }
}

resource "aws_rds_cluster_instance" "aurora_mysql" {
  identifier           = "${local.name_prefix}-aurora-mysql-1"
  cluster_identifier   = aws_rds_cluster.aurora_mysql.id
  instance_class       = var.aurora_instance_class
  engine               = aws_rds_cluster.aurora_mysql.engine
  engine_version       = aws_rds_cluster.aurora_mysql.engine_version
  db_subnet_group_name = aws_db_subnet_group.aurora.name

  tags = {
    Name = "${local.name_prefix}-aurora-mysql-1"
  }
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${local.name_prefix}-aurora-credentials"
  description = "Credentials used by RDS Proxy to connect to the Aurora MySQL cluster"

  tags = {
    Name = "${local.name_prefix}-aurora-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.master_username
    password = var.master_password
    engine   = "mysql"
    host     = aws_rds_cluster.aurora_mysql.endpoint
    port     = 3306
    dbname   = local.db_name
  })
}

data "aws_iam_policy_document" "rds_proxy_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "rds_proxy" {
  name               = "${local.name_prefix}-rds-proxy-role"
  assume_role_policy = data.aws_iam_policy_document.rds_proxy_assume_role.json

  tags = {
    Name = "${local.name_prefix}-rds-proxy-role"
  }
}

data "aws_iam_policy_document" "rds_proxy_secret_access" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [aws_secretsmanager_secret.db_credentials.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt"
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.us-east-1.amazonaws.com"]
    }
  }
}

resource "aws_iam_role_policy" "rds_proxy_secret_access" {
  name   = "${local.name_prefix}-rds-proxy-secret-access"
  role   = aws_iam_role.rds_proxy.id
  policy = data.aws_iam_policy_document.rds_proxy_secret_access.json
}

resource "aws_db_proxy" "mysql" {
  name                   = "${local.name_prefix}-mysql-proxy"
  debug_logging          = false
  engine_family          = "MYSQL"
  idle_client_timeout    = 1800
  require_tls            = true
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_security_group_ids = [aws_security_group.database.id]
  vpc_subnet_ids         = [for subnet in aws_subnet.private : subnet.id]

  auth {
    auth_scheme = "SECRETS"
    description = "Secrets Manager authentication for Aurora MySQL"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.db_credentials.arn
  }

  tags = {
    Name = "${local.name_prefix}-mysql-proxy"
  }

  depends_on = [
    aws_iam_role_policy.rds_proxy_secret_access,
    aws_secretsmanager_secret_version.db_credentials
  ]
}

resource "aws_db_proxy_default_target_group" "mysql" {
  db_proxy_name = aws_db_proxy.mysql.name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 100
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "aurora_cluster" {
  db_cluster_identifier = aws_rds_cluster.aurora_mysql.cluster_identifier
  db_proxy_name         = aws_db_proxy.mysql.name
  target_group_name     = aws_db_proxy_default_target_group.mysql.name

  depends_on = [aws_rds_cluster_instance.aurora_mysql]
}

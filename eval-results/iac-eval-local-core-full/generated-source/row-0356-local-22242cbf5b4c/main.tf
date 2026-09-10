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

locals {
  name_prefix = var.name_prefix
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_subnet" "database" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.database_subnet_cidr_blocks[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-db-${count.index + 1}"
  }
}

resource "aws_security_group" "rds" {
  name_prefix = "${local.name_prefix}-rds-"
  description = "Allow MySQL traffic from application clients to Aurora and the RDS proxy"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "MySQL from configured client CIDR blocks"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = var.client_cidr_blocks
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-rds-sg"
  }
}

resource "aws_db_subnet_group" "database" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = aws_subnet.database[*].id

  tags = {
    Name = "${local.name_prefix}-db-subnet-group"
  }
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${local.name_prefix}/aurora-mysql/credentials"
  description             = "Credentials for ${local.name_prefix} Aurora MySQL cluster and RDS proxy"
  recovery_window_in_days = 7

  tags = {
    Name = "${local.name_prefix}-db-credentials"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = var.db_master_username
    password = var.db_master_password
  })
}

resource "aws_iam_role" "rds_proxy" {
  name = "${local.name_prefix}-rds-proxy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${local.name_prefix}-rds-proxy-role"
  }
}

resource "aws_iam_role_policy" "rds_proxy_secrets" {
  name = "${local.name_prefix}-rds-proxy-secrets"
  role = aws_iam_role.rds_proxy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret"
        ]
        Resource = aws_secretsmanager_secret.db_credentials.arn
      }
    ]
  })
}

resource "aws_rds_cluster" "aurora_mysql" {
  cluster_identifier     = "${local.name_prefix}-aurora-mysql"
  engine                 = "aurora-mysql"
  engine_version         = "8.0.mysql_aurora.3.08.0"
  database_name          = var.database_name
  master_username        = var.db_master_username
  master_password        = var.db_master_password
  db_subnet_group_name   = aws_db_subnet_group.database.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true

  tags = {
    Name = "${local.name_prefix}-aurora-mysql"
  }
}

resource "aws_rds_cluster_instance" "aurora_mysql" {
  identifier           = "${local.name_prefix}-aurora-mysql-1"
  cluster_identifier   = aws_rds_cluster.aurora_mysql.id
  instance_class       = "db.r6g.large"
  engine               = aws_rds_cluster.aurora_mysql.engine
  engine_version       = aws_rds_cluster.aurora_mysql.engine_version
  db_subnet_group_name = aws_db_subnet_group.database.name

  tags = {
    Name = "${local.name_prefix}-aurora-mysql-1"
  }
}

resource "aws_db_proxy" "aurora_mysql" {
  name                   = "${local.name_prefix}-aurora-mysql-proxy"
  debug_logging          = false
  engine_family          = "MYSQL"
  idle_client_timeout    = 1800
  require_tls            = true
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_security_group_ids = [aws_security_group.rds.id]
  vpc_subnet_ids         = aws_subnet.database[*].id

  auth {
    auth_scheme = "SECRETS"
    description = "Secrets Manager credentials for Aurora MySQL"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.db_credentials.arn
  }

  depends_on = [
    aws_iam_role_policy.rds_proxy_secrets,
    aws_secretsmanager_secret_version.db_credentials
  ]

  tags = {
    Name = "${local.name_prefix}-aurora-mysql-proxy"
  }
}

resource "aws_db_proxy_default_target_group" "aurora_mysql" {
  db_proxy_name = aws_db_proxy.aurora_mysql.name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 100
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "aurora_mysql_cluster" {
  db_proxy_name         = aws_db_proxy.aurora_mysql.name
  target_group_name     = aws_db_proxy_default_target_group.aurora_mysql.name
  db_cluster_identifier = aws_rds_cluster.aurora_mysql.id

  depends_on = [aws_rds_cluster_instance.aurora_mysql]
}

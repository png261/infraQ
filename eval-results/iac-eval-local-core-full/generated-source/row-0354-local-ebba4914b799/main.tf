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

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "aurora-mysql-proxy"
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
  cidr_block              = cidrsubnet(var.vpc_cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_prefix}-db-${count.index + 1}"
  }
}

resource "aws_security_group" "proxy_clients" {
  name        = "${local.name_prefix}-clients"
  description = "Allow EC2/application clients to reach the RDS proxy"
  vpc_id      = aws_vpc.main.id

  egress {
    description     = "MySQL to RDS proxy"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.rds.id]
  }

  tags = {
    Name = "${local.name_prefix}-clients"
  }
}

resource "aws_security_group" "rds" {
  name        = "${local.name_prefix}-rds"
  description = "Allow MySQL traffic from EC2/application clients and proxy"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "MySQL from application clients"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.proxy_clients.id]
  }

  ingress {
    description = "MySQL between RDS proxy and Aurora cluster"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "Allow outbound responses"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-rds"
  }
}

resource "aws_db_subnet_group" "database" {
  name       = "${local.name_prefix}-subnets"
  subnet_ids = aws_subnet.database[*].id

  tags = {
    Name = "${local.name_prefix}-subnets"
  }
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${local.name_prefix}-credentials"
  description = "Aurora MySQL credentials used by the RDS proxy"
}

# Benchmark requires aws_secretsmanager_secret_version. The secret value is sensitive,
# but Terraform/OpenTofu will still store it in state; protect state accordingly.
resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_master_username
    password = var.db_master_password
  })
}

resource "aws_iam_role" "rds_proxy" {
  name = "${local.name_prefix}-role"

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
}

resource "aws_iam_role_policy" "rds_proxy_secrets" {
  name = "${local.name_prefix}-secrets-access"
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

resource "aws_rds_cluster" "aurora" {
  cluster_identifier     = "${local.name_prefix}-cluster"
  engine                 = "aurora-mysql"
  engine_mode            = "provisioned"
  database_name          = var.db_name
  master_username        = var.db_master_username
  master_password        = var.db_master_password
  db_subnet_group_name   = aws_db_subnet_group.database.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  skip_final_snapshot    = true

  depends_on = [aws_secretsmanager_secret_version.db_credentials]
}

resource "aws_rds_cluster_instance" "aurora" {
  identifier         = "${local.name_prefix}-instance-1"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = var.db_instance_class
  engine             = aws_rds_cluster.aurora.engine
}

resource "aws_db_proxy" "mysql" {
  name                   = "${local.name_prefix}-proxy"
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

  depends_on = [aws_iam_role_policy.rds_proxy_secrets]
}

resource "aws_db_proxy_default_target_group" "mysql" {
  db_proxy_name = aws_db_proxy.mysql.name

  connection_pool_config {
    max_connections_percent      = 90
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "aurora" {
  db_cluster_identifier = aws_rds_cluster.aurora.cluster_identifier
  db_proxy_name         = aws_db_proxy.mysql.name
  target_group_name     = aws_db_proxy_default_target_group.mysql.name
}

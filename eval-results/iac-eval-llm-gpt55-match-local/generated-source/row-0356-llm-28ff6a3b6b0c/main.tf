terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming."
  type        = string
  default     = "aurora-mysql-proxy-demo"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Aurora MySQL master username."
  type        = string
  default     = "adminuser"
}

variable "db_instance_class" {
  description = "Aurora DB instance class."
  type        = string
  default     = "db.r6g.large"
}

variable "allowed_proxy_cidr" {
  description = "CIDR block allowed to connect to the RDS Proxy. Adjust for your application network."
  type        = string
  default     = "10.0.0.0/16"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  common_tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-${count.index + 1}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 10)
  availability_zone = local.azs[count.index]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-${count.index + 1}"
    Tier = "private"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "rds_proxy" {
  name        = "${var.project_name}-proxy-sg"
  description = "Security group for RDS Proxy"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow MySQL access to RDS Proxy from application CIDR"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.allowed_proxy_cidr]
  }

  egress {
    description = "Allow outbound traffic from RDS Proxy"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-proxy-sg"
  })
}

resource "aws_security_group" "aurora" {
  name        = "${var.project_name}-aurora-sg"
  description = "Security group for Aurora MySQL cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow MySQL from RDS Proxy"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.rds_proxy.id]
  }

  egress {
    description = "Allow outbound traffic from Aurora"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-aurora-sg"
  })
}

resource "aws_db_subnet_group" "aurora" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-db-subnet-group"
  })
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}/aurora/mysql/credentials"
  description             = "Credentials for Aurora MySQL cluster used by RDS Proxy"
  recovery_window_in_days = 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
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
  name               = "${var.project_name}-rds-proxy-role"
  assume_role_policy = data.aws_iam_policy_document.rds_proxy_assume_role.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "rds_proxy_secrets_access" {
  statement {
    sid    = "AllowReadDatabaseSecret"
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]

    resources = [
      aws_secretsmanager_secret.db_credentials.arn
    ]
  }

  statement {
    sid    = "AllowKmsDecryptForSecretsManager"
    effect = "Allow"

    actions = [
      "kms:Decrypt"
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${var.aws_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "rds_proxy_secrets_access" {
  name        = "${var.project_name}-rds-proxy-secrets-policy"
  description = "Allows RDS Proxy to read Aurora credentials from Secrets Manager"
  policy      = data.aws_iam_policy_document.rds_proxy_secrets_access.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_proxy_secrets_access" {
  role       = aws_iam_role.rds_proxy.name
  policy_arn = aws_iam_policy.rds_proxy_secrets_access.arn
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier              = "${var.project_name}-cluster"
  engine                          = "aurora-mysql"
  engine_version                  = "8.0.mysql_aurora.3.08.0"
  database_name                   = var.db_name
  master_username                 = var.db_username
  master_password                 = random_password.db_password.result
  db_subnet_group_name            = aws_db_subnet_group.aurora.name
  vpc_security_group_ids          = [aws_security_group.aurora.id]
  port                            = 3306
  storage_encrypted               = true
  backup_retention_period         = 7
  preferred_backup_window         = "03:00-04:00"
  preferred_maintenance_window    = "sun:04:00-sun:05:00"
  deletion_protection             = false
  skip_final_snapshot             = true
  apply_immediately               = true
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]

  depends_on = [
    aws_secretsmanager_secret_version.db_credentials
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-cluster"
  })
}

resource "aws_rds_cluster_instance" "aurora" {
  count = 2

  identifier                   = "${var.project_name}-instance-${count.index + 1}"
  cluster_identifier           = aws_rds_cluster.aurora.id
  instance_class               = var.db_instance_class
  engine                       = aws_rds_cluster.aurora.engine
  engine_version               = aws_rds_cluster.aurora.engine_version
  db_subnet_group_name         = aws_db_subnet_group.aurora.name
  publicly_accessible          = false
  auto_minor_version_upgrade   = true
  performance_insights_enabled = true
  monitoring_interval          = 0
  apply_immediately            = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-instance-${count.index + 1}"
  })
}

resource "aws_db_proxy" "aurora" {
  name                   = "${var.project_name}-proxy"
  debug_logging          = false
  engine_family          = "MYSQL"
  idle_client_timeout    = 1800
  require_tls            = true
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_security_group_ids = [aws_security_group.rds_proxy.id]
  vpc_subnet_ids         = aws_subnet.private[*].id

  auth {
    auth_scheme = "SECRETS"
    description = "Secrets Manager credentials for Aurora MySQL"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.db_credentials.arn
  }

  depends_on = [
    aws_iam_role_policy_attachment.rds_proxy_secrets_access,
    aws_rds_cluster_instance.aurora
  ]

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-proxy"
  })
}

resource "aws_db_proxy_default_target_group" "aurora" {
  db_proxy_name = aws_db_proxy.aurora.name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 90
    max_idle_connections_percent = 50
    session_pinning_filters      = ["EXCLUDE_VARIABLE_SETS"]
  }
}

resource "aws_db_proxy_target" "aurora_cluster" {
  db_proxy_name         = aws_db_proxy.aurora.name
  target_group_name     = aws_db_proxy_default_target_group.aurora.name
  db_cluster_identifier = aws_rds_cluster.aurora.cluster_identifier

  depends_on = [
    aws_db_proxy_default_target_group.aurora,
    aws_rds_cluster_instance.aurora
  ]
}

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.main.id
}

output "aurora_cluster_endpoint" {
  description = "Aurora cluster writer endpoint."
  value       = aws_rds_cluster.aurora.endpoint
}

output "aurora_reader_endpoint" {
  description = "Aurora cluster reader endpoint."
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "rds_proxy_endpoint" {
  description = "RDS Proxy endpoint for application connections."
  value       = aws_db_proxy.aurora.endpoint
}

output "db_secret_arn" {
  description = "Secrets Manager secret ARN containing database credentials."
  value       = aws_secretsmanager_secret.db_credentials.arn
}

output "db_name" {
  description = "Initial database name."
  value       = var.db_name
}

output "db_username" {
  description = "Database username."
  value       = var.db_username
}
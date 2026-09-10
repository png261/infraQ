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
  default     = "aurora-mysql-proxy"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "appdb"
}

variable "db_master_username" {
  description = "Master username for Aurora MySQL."
  type        = string
  default     = "adminuser"
}

variable "db_instance_class" {
  description = "Aurora MySQL DB instance class."
  type        = string
  default     = "db.r6g.large"
}

variable "db_instance_count" {
  description = "Number of Aurora cluster instances."
  type        = number
  default     = 2
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  public_subnet_cidrs = [
    "10.20.0.0/24",
    "10.20.1.0/24"
  ]

  private_subnet_cidrs = [
    "10.20.10.0/24",
    "10.20.11.0/24"
  ]

  common_tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

resource "random_password" "db_master_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
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
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-${count.index + 1}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.private_subnet_cidrs[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-private-${count.index + 1}"
    Tier = "private"
  })
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat-eip"
  })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-nat"
  })

  depends_on = [
    aws_internet_gateway.main
  ]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route" "public_default_ipv4" {
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

resource "aws_route" "private_default_ipv4" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.main.id
}

resource "aws_route_table_association" "private" {
  count = 2

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "app" {
  name        = "${var.project_name}-app-sg"
  description = "Security group for application clients that connect to the RDS Proxy."
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow outbound traffic to the RDS Proxy."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-app-sg"
  })
}

resource "aws_security_group" "rds_proxy" {
  name        = "${var.project_name}-proxy-sg"
  description = "Security group for RDS Proxy."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow MySQL connections from application security group."
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]
  }

  egress {
    description     = "Allow MySQL traffic to Aurora security group."
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.aurora.id]
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-proxy-sg"
  })
}

resource "aws_security_group" "aurora" {
  name        = "${var.project_name}-aurora-sg"
  description = "Security group for Aurora MySQL cluster."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow MySQL from RDS Proxy only."
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.rds_proxy.id]
  }

  egress {
    description = "Allow outbound traffic."
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
  name        = "${var.project_name}-db-subnet-group"
  description = "Private subnet group for Aurora MySQL."
  subnet_ids  = aws_subnet.private[*].id

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-db-subnet-group"
  })
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}/aurora/mysql/credentials"
  description             = "Aurora MySQL credentials for RDS Proxy."
  recovery_window_in_days = 0

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-db-credentials"
  })
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = var.db_master_username
    password = random_password.db_master_password.result
    engine   = "mysql"
    port     = 3306
    dbname   = var.db_name
  })
}

resource "aws_rds_cluster" "aurora_mysql" {
  cluster_identifier      = "${var.project_name}-cluster"
  engine                  = "aurora-mysql"
  database_name           = var.db_name
  master_username         = var.db_master_username
  master_password         = random_password.db_master_password.result
  db_subnet_group_name    = aws_db_subnet_group.aurora.name
  vpc_security_group_ids  = [aws_security_group.aurora.id]
  storage_encrypted       = true
  backup_retention_period = 7
  preferred_backup_window = "03:00-04:00"

  skip_final_snapshot       = false
  final_snapshot_identifier = "snapshot"

  deletion_protection = false
  apply_immediately   = true

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-cluster"
  })

  depends_on = [
    aws_secretsmanager_secret_version.db_credentials
  ]
}

resource "aws_rds_cluster_instance" "aurora_mysql" {
  count = var.db_instance_count

  identifier          = "${var.project_name}-instance-${count.index + 1}"
  cluster_identifier  = aws_rds_cluster.aurora_mysql.id
  instance_class      = var.db_instance_class
  engine              = aws_rds_cluster.aurora_mysql.engine
  db_subnet_group_name = aws_db_subnet_group.aurora.name
  publicly_accessible = false

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-instance-${count.index + 1}"
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

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-rds-proxy-role"
  })
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
  name        = "${var.project_name}-rds-proxy-secrets-access"
  description = "Allows RDS Proxy to read Aurora MySQL credentials from Secrets Manager."
  policy      = data.aws_iam_policy_document.rds_proxy_secrets_access.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_proxy_secrets_access" {
  role       = aws_iam_role.rds_proxy.name
  policy_arn = aws_iam_policy.rds_proxy_secrets_access.arn
}

resource "aws_db_proxy" "aurora_mysql" {
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
    description = "Secrets Manager authentication for Aurora MySQL."
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.db_credentials.arn
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-proxy"
  })

  depends_on = [
    aws_iam_role_policy_attachment.rds_proxy_secrets_access,
    aws_secretsmanager_secret_version.db_credentials,
    aws_rds_cluster_instance.aurora_mysql
  ]
}

resource "aws_db_proxy_default_target_group" "aurora_mysql" {
  db_proxy_name = aws_db_proxy.aurora_mysql.name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 90
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "aurora_mysql_cluster" {
  db_proxy_name         = aws_db_proxy.aurora_mysql.name
  target_group_name     = aws_db_proxy_default_target_group.aurora_mysql.name
  db_cluster_identifier = aws_rds_cluster.aurora_mysql.cluster_identifier

  depends_on = [
    aws_rds_cluster_instance.aurora_mysql
  ]
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "private_subnet_ids" {
  description = "Private subnet IDs used by Aurora and RDS Proxy."
  value       = aws_subnet.private[*].id
}

output "app_security_group_id" {
  description = "Security group ID that application resources should use to connect to the RDS Proxy."
  value       = aws_security_group.app.id
}

output "aurora_cluster_endpoint" {
  description = "Aurora MySQL writer endpoint."
  value       = aws_rds_cluster.aurora_mysql.endpoint
}

output "aurora_cluster_reader_endpoint" {
  description = "Aurora MySQL reader endpoint."
  value       = aws_rds_cluster.aurora_mysql.reader_endpoint
}

output "rds_proxy_endpoint" {
  description = "RDS Proxy endpoint for application database connections."
  value       = aws_db_proxy.aurora_mysql.endpoint
}

output "db_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret containing database credentials."
  value       = aws_secretsmanager_secret.db_credentials.arn
  sensitive   = true
}
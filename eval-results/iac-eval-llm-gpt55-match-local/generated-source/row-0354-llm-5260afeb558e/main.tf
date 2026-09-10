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
  description = "AWS region where resources will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "aurora-mysql-proxy-demo"
}

variable "db_name" {
  description = "Initial Aurora MySQL database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for Aurora MySQL."
  type        = string
  default     = "adminuser"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "private_subnet_cidrs" {
  description = "CIDR blocks for private subnets."
  type        = list(string)
  default     = ["10.20.1.0/24", "10.20.2.0/24"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets."
  type        = list(string)
  default     = ["10.20.101.0/24", "10.20.102.0/24"]
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
  name_prefix = var.project_name

  common_tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-${count.index + 1}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_cidrs[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-${count.index + 1}"
    Tier = "private"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
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

resource "aws_security_group" "rds_proxy" {
  name        = "${local.name_prefix}-rds-proxy-sg"
  description = "Security group for RDS Proxy"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow MySQL connections to RDS Proxy from within VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Allow outbound traffic from RDS Proxy"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-proxy-sg"
  })
}

resource "aws_security_group" "aurora" {
  name        = "${local.name_prefix}-aurora-sg"
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
    Name = "${local.name_prefix}-aurora-sg"
  })
}

resource "aws_db_subnet_group" "aurora" {
  name       = "${local.name_prefix}-aurora-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-aurora-subnet-group"
  })
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${local.name_prefix}/aurora/mysql/credentials"
  description             = "Aurora MySQL credentials for RDS Proxy"
  recovery_window_in_days = 0

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-credentials"
  })
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db_password.result
    engine   = "mysql"
    host     = aws_rds_cluster.aurora.endpoint
    port     = 3306
    dbname   = var.db_name
  })
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier      = "${local.name_prefix}-cluster"
  engine                  = "aurora-mysql"
  engine_mode             = "provisioned"
  database_name           = var.db_name
  master_username         = var.db_username
  master_password         = random_password.db_password.result
  db_subnet_group_name    = aws_db_subnet_group.aurora.name
  vpc_security_group_ids  = [aws_security_group.aurora.id]
  storage_encrypted       = true
  backup_retention_period = 7
  preferred_backup_window = "03:00-04:00"
  skip_final_snapshot     = true
  apply_immediately       = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-aurora-cluster"
  })
}

resource "aws_rds_cluster_instance" "aurora_instance" {
  count = 1

  identifier          = "${local.name_prefix}-instance-${count.index + 1}"
  cluster_identifier  = aws_rds_cluster.aurora.id
  instance_class      = "db.t3.medium"
  engine              = aws_rds_cluster.aurora.engine
  db_subnet_group_name = aws_db_subnet_group.aurora.name
  publicly_accessible = false
  apply_immediately   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-aurora-instance-${count.index + 1}"
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

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-proxy-role"
  })
}

resource "aws_iam_policy" "rds_proxy_secret_access" {
  name        = "${local.name_prefix}-rds-proxy-secret-access"
  description = "Allow RDS Proxy to read Aurora MySQL credentials from Secrets Manager"

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
      },
      {
        Effect = "Allow"
        Action = [
          "kms:Decrypt"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "secretsmanager.${var.aws_region}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-proxy-secret-access"
  })
}

resource "aws_iam_role_policy_attachment" "rds_proxy_secret_access" {
  role       = aws_iam_role.rds_proxy.name
  policy_arn = aws_iam_policy.rds_proxy_secret_access.arn
}

resource "aws_db_proxy" "aurora_mysql" {
  name                   = "${local.name_prefix}-proxy"
  debug_logging          = false
  engine_family          = "MYSQL"
  idle_client_timeout    = 1800
  require_tls            = true
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_security_group_ids = [aws_security_group.rds_proxy.id]
  vpc_subnet_ids         = aws_subnet.private[*].id

  auth {
    auth_scheme = "SECRETS"
    description = "Secrets Manager authentication for Aurora MySQL"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.db_credentials.arn
  }

  depends_on = [
    aws_iam_role_policy_attachment.rds_proxy_secret_access,
    aws_secretsmanager_secret_version.db_credentials,
    aws_rds_cluster_instance.aurora_instance
  ]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-rds-proxy"
  })
}

resource "aws_db_proxy_default_target_group" "aurora_mysql" {
  db_proxy_name = aws_db_proxy.aurora_mysql.name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 100
    max_idle_connections_percent = 50
    session_pinning_filters      = []
  }
}

resource "aws_db_proxy_target" "aurora_cluster" {
  db_proxy_name         = aws_db_proxy.aurora_mysql.name
  target_group_name     = aws_db_proxy_default_target_group.aurora_mysql.name
  db_cluster_identifier = aws_rds_cluster.aurora.cluster_identifier

  depends_on = [
    aws_rds_cluster_instance.aurora_instance
  ]
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "aurora_cluster_endpoint" {
  description = "Aurora MySQL cluster writer endpoint."
  value       = aws_rds_cluster.aurora.endpoint
}

output "aurora_cluster_reader_endpoint" {
  description = "Aurora MySQL cluster reader endpoint."
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "rds_proxy_endpoint" {
  description = "RDS Proxy endpoint for application connections."
  value       = aws_db_proxy.aurora_mysql.endpoint
}

output "db_credentials_secret_arn" {
  description = "ARN of the Secrets Manager secret containing database credentials."
  value       = aws_secretsmanager_secret.db_credentials.arn
}
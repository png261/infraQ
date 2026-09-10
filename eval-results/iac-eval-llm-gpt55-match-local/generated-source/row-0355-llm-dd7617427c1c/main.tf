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

provider "random" {}

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "aurora-mysql-proxy-demo"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master database username."
  type        = string
  default     = "adminuser"
}

variable "db_instance_class" {
  description = "Aurora MySQL instance class."
  type        = string
  default     = "db.r6g.large"
}

variable "db_engine_version" {
  description = "Aurora MySQL engine version."
  type        = string
  default     = "8.0.mysql_aurora.3.05.2"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "random_password" "db_password" {
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.40.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.40.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-b"
  }
}

resource "aws_db_subnet_group" "aurora" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

resource "aws_security_group" "rds_proxy" {
  name        = "${var.project_name}-proxy-sg"
  description = "Security group for RDS Proxy"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow MySQL access to RDS Proxy from within VPC"
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

  tags = {
    Name = "${var.project_name}-proxy-sg"
  }
}

resource "aws_security_group" "aurora" {
  name        = "${var.project_name}-aurora-sg"
  description = "Security group for Aurora MySQL cluster"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow MySQL traffic from RDS Proxy"
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

  tags = {
    Name = "${var.project_name}-aurora-sg"
  }
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}-db-credentials"
  description             = "Credentials for Aurora MySQL cluster and RDS Proxy"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-db-credentials"
  }
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

resource "aws_iam_role" "rds_proxy" {
  name = "${var.project_name}-rds-proxy-role"

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
    Name = "${var.project_name}-rds-proxy-role"
  }
}

resource "aws_iam_policy" "rds_proxy_secret_access" {
  name        = "${var.project_name}-rds-proxy-secret-access"
  description = "Allows RDS Proxy to read database credentials from Secrets Manager"

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
}

resource "aws_iam_role_policy_attachment" "rds_proxy_secret_access" {
  role       = aws_iam_role.rds_proxy.name
  policy_arn = aws_iam_policy.rds_proxy_secret_access.arn
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier      = "${var.project_name}-cluster"
  engine                  = "aurora-mysql"
  engine_version          = var.db_engine_version
  database_name           = var.db_name
  master_username         = var.db_username
  master_password         = random_password.db_password.result
  db_subnet_group_name    = aws_db_subnet_group.aurora.name
  vpc_security_group_ids  = [aws_security_group.aurora.id]
  port                    = 3306

  backup_retention_period = 5
  preferred_backup_window = "07:00-09:00"

  storage_encrypted               = true
  deletion_protection             = false
  skip_final_snapshot             = true
  apply_immediately               = true
  copy_tags_to_snapshot           = true
  enabled_cloudwatch_logs_exports = ["audit", "error", "general", "slowquery"]

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

resource "aws_rds_cluster_instance" "aurora_instances" {
  count = 2

  identifier           = "${var.project_name}-instance-${count.index + 1}"
  cluster_identifier   = aws_rds_cluster.aurora.id
  instance_class       = var.db_instance_class
  engine               = aws_rds_cluster.aurora.engine
  engine_version       = aws_rds_cluster.aurora.engine_version
  db_subnet_group_name = aws_db_subnet_group.aurora.name

  publicly_accessible = false
  apply_immediately   = true

  tags = {
    Name = "${var.project_name}-instance-${count.index + 1}"
  }
}

resource "aws_db_proxy" "aurora_proxy" {
  name                   = "${var.project_name}-proxy"
  debug_logging          = false
  engine_family          = "MYSQL"
  idle_client_timeout    = 1800
  require_tls            = true
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_security_group_ids = [aws_security_group.rds_proxy.id]
  vpc_subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  auth {
    auth_scheme = "SECRETS"
    description = "Secrets Manager authentication for Aurora MySQL"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.db_credentials.arn
  }

  depends_on = [
    aws_iam_role_policy_attachment.rds_proxy_secret_access,
    aws_secretsmanager_secret_version.db_credentials
  ]

  tags = {
    Name = "${var.project_name}-proxy"
  }
}

resource "aws_db_proxy_default_target_group" "aurora_proxy_default" {
  db_proxy_name = aws_db_proxy.aurora_proxy.name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 90
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "aurora_cluster" {
  db_proxy_name         = aws_db_proxy.aurora_proxy.name
  target_group_name     = aws_db_proxy_default_target_group.aurora_proxy_default.name
  db_cluster_identifier = aws_rds_cluster.aurora.cluster_identifier

  depends_on = [
    aws_rds_cluster_instance.aurora_instances
  ]
}

output "aurora_cluster_endpoint" {
  description = "Aurora MySQL cluster writer endpoint."
  value       = aws_rds_cluster.aurora.endpoint
}

output "aurora_reader_endpoint" {
  description = "Aurora MySQL cluster reader endpoint."
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "rds_proxy_endpoint" {
  description = "RDS Proxy endpoint for application connections."
  value       = aws_db_proxy.aurora_proxy.endpoint
}

output "db_secret_arn" {
  description = "Secrets Manager ARN containing database credentials."
  value       = aws_secretsmanager_secret.db_credentials.arn
}
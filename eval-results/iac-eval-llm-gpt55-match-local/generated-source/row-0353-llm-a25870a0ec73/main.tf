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
  description = "AWS region for the deployment."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "aurora-mysql-proxy"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.40.0.0/16"
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
  description = "Aurora MySQL instance class."
  type        = string
  default     = "db.t3.medium"
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
  cidr_block           = var.vpc_cidr
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

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-private-rt"
  }
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "rds_proxy" {
  name        = "${var.project_name}-proxy-sg"
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
    description     = "Allow proxy to connect to Aurora MySQL"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.aurora.id]
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

  tags = {
    Name = "${var.project_name}-aurora-sg"
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

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}/aurora/mysql/credentials"
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
  })
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier      = "${var.project_name}-cluster"
  engine                  = "aurora-mysql"
  database_name           = var.db_name
  master_username         = var.db_username
  master_password         = random_password.db_password.result
  db_subnet_group_name    = aws_db_subnet_group.aurora.name
  vpc_security_group_ids  = [aws_security_group.aurora.id]
  storage_encrypted       = true
  backup_retention_period = 7
  preferred_backup_window = "03:00-04:00"
  skip_final_snapshot     = true
  deletion_protection     = false

  depends_on = [
    aws_secretsmanager_secret_version.db_credentials
  ]

  tags = {
    Name = "${var.project_name}-cluster"
  }
}

resource "aws_rds_cluster_instance" "aurora_instance_1" {
  identifier         = "${var.project_name}-instance-1"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = var.db_instance_class
  engine             = aws_rds_cluster.aurora.engine

  tags = {
    Name = "${var.project_name}-instance-1"
  }
}

resource "aws_rds_cluster_instance" "aurora_instance_2" {
  identifier         = "${var.project_name}-instance-2"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = var.db_instance_class
  engine             = aws_rds_cluster.aurora.engine

  tags = {
    Name = "${var.project_name}-instance-2"
  }
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

resource "aws_iam_policy" "rds_proxy_secrets_access" {
  name        = "${var.project_name}-rds-proxy-secrets-access"
  description = "Allow RDS Proxy to read database credentials from Secrets Manager"

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

  vpc_subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id
  ]

  auth {
    auth_scheme = "SECRETS"
    description = "Aurora MySQL credentials from Secrets Manager"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.db_credentials.arn
  }

  depends_on = [
    aws_iam_role_policy_attachment.rds_proxy_secrets_access,
    aws_rds_cluster_instance.aurora_instance_1,
    aws_rds_cluster_instance.aurora_instance_2
  ]

  tags = {
    Name = "${var.project_name}-proxy"
  }
}

resource "aws_db_proxy_default_target_group" "aurora_mysql" {
  db_proxy_name = aws_db_proxy.aurora_mysql.name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 90
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "aurora_cluster" {
  db_proxy_name         = aws_db_proxy.aurora_mysql.name
  target_group_name     = aws_db_proxy_default_target_group.aurora_mysql.name
  db_cluster_identifier = aws_rds_cluster.aurora.cluster_identifier

  depends_on = [
    aws_db_proxy_default_target_group.aurora_mysql,
    aws_rds_cluster_instance.aurora_instance_1,
    aws_rds_cluster_instance.aurora_instance_2
  ]
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "aurora_cluster_endpoint" {
  description = "Aurora MySQL writer endpoint."
  value       = aws_rds_cluster.aurora.endpoint
}

output "aurora_reader_endpoint" {
  description = "Aurora MySQL reader endpoint."
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "rds_proxy_endpoint" {
  description = "RDS Proxy endpoint for application connections."
  value       = aws_db_proxy.aurora_mysql.endpoint
}

output "db_secret_arn" {
  description = "ARN of the Secrets Manager secret containing database credentials."
  value       = aws_secretsmanager_secret.db_credentials.arn
}
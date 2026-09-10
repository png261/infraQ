terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "db_identifier" {
  description = "Identifier for the RDS database instance."
  type        = string
  default     = "managed-master-password-db"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username for the RDS database."
  type        = string
  default     = "dbadmin"
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default_vpc_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_kms_key" "rds_secrets_key" {
  description             = "Customer managed KMS key for RDS managed master password secret"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "rds-secrets-kms-key-policy"
    Statement = [
      {
        Sid    = "EnableRootAccountPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowSecretsManagerUseOfKey"
        Effect = "Allow"
        Principal = {
          Service = "secretsmanager.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:ReEncryptFrom",
          "kms:ReEncryptTo",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowRDSUseOfKey"
        Effect = "Allow"
        Principal = {
          Service = "rds.amazonaws.com"
        }
        Action = [
          "kms:Decrypt",
          "kms:Encrypt",
          "kms:ReEncryptFrom",
          "kms:ReEncryptTo",
          "kms:GenerateDataKey",
          "kms:DescribeKey",
          "kms:CreateGrant"
        ]
        Resource = "*"
      }
    ]
  })

  tags = {
    Name = "rds-managed-master-password-kms-key"
  }
}

resource "aws_kms_alias" "rds_secrets_key_alias" {
  name          = "alias/rds-managed-master-password-key"
  target_key_id = aws_kms_key.rds_secrets_key.key_id
}

resource "aws_db_subnet_group" "default" {
  name       = "${var.db_identifier}-subnet-group"
  subnet_ids = data.aws_subnets.default_vpc_subnets.ids

  tags = {
    Name = "${var.db_identifier}-subnet-group"
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.db_identifier}-sg"
  description = "Security group for RDS PostgreSQL database"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow PostgreSQL access from within the default VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.db_identifier}-sg"
  }
}

resource "aws_db_instance" "postgres" {
  identifier = var.db_identifier

  engine         = "postgres"
  engine_version = "16.3"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = var.db_name
  username = var.db_username

  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.rds_secrets_key.arn

  db_subnet_group_name   = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  deletion_protection = false
  skip_final_snapshot = true

  auto_minor_version_upgrade = true

  tags = {
    Name = var.db_identifier
  }
}

output "rds_instance_endpoint" {
  description = "RDS database endpoint."
  value       = aws_db_instance.postgres.endpoint
}

output "rds_instance_identifier" {
  description = "RDS database instance identifier."
  value       = aws_db_instance.postgres.id
}

output "rds_master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret managed by RDS for the master user password."
  value       = aws_db_instance.postgres.master_user_secret[0].secret_arn
}

output "kms_key_arn" {
  description = "ARN of the customer-managed KMS key used for the RDS master user secret."
  value       = aws_kms_key.rds_secrets_key.arn
}
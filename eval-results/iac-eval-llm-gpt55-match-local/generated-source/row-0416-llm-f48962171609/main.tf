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
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "restoredappdb"
}

variable "db_username" {
  description = "Master username for the RDS instance."
  type        = string
  default     = "adminuser"
}

variable "db_password" {
  description = "Master password for the RDS instance."
  type        = string
  sensitive   = true
  default     = "ChangeMe123456789!"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "mysql_engine_version" {
  description = "MySQL engine version for RDS."
  type        = string
  default     = "8.0.35"
}

variable "s3_import_prefix" {
  description = "S3 prefix containing the MySQL backup files to import."
  type        = string
  default     = "mysql-backup/"
}

resource "random_id" "suffix" {
  byte_length = 4
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_s3_bucket" "mysql_backup" {
  bucket        = "rds-mysql-s3-restore-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "mysql_backup" {
  bucket = aws_s3_bucket.mysql_backup.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "mysql_backup" {
  bucket = aws_s3_bucket.mysql_backup.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_iam_role" "rds_s3_import" {
  name = "rds-s3-import-role-${random_id.suffix.hex}"

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

resource "aws_iam_policy" "rds_s3_import" {
  name        = "rds-s3-import-policy-${random_id.suffix.hex}"
  description = "Allows RDS to import MySQL backup files from S3."

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.mysql_backup.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.mysql_backup.arn}/*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rds_s3_import" {
  role       = aws_iam_role.rds_s3_import.name
  policy_arn = aws_iam_policy.rds_s3_import.arn
}

resource "aws_db_subnet_group" "mysql" {
  name       = "mysql-restore-subnet-group-${random_id.suffix.hex}"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "mysql-restore-subnet-group"
  }
}

resource "aws_security_group" "rds_mysql" {
  name        = "rds-mysql-restore-sg-${random_id.suffix.hex}"
  description = "Security group for restored MySQL RDS instance"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow MySQL access from within the default VPC"
    from_port   = 3306
    to_port     = 3306
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
    Name = "rds-mysql-restore-sg"
  }
}

resource "aws_db_instance" "restored_from_s3" {
  identifier = "mysql-restored-from-s3-${random_id.suffix.hex}"

  engine         = "mysql"
  engine_version = var.mysql_engine_version
  instance_class = var.db_instance_class

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [aws_security_group.rds_mysql.id]

  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = true

  apply_immediately = true

  s3_import {
    source_engine         = "mysql"
    source_engine_version = "8.0"
    bucket_name           = aws_s3_bucket.mysql_backup.bucket
    bucket_prefix         = var.s3_import_prefix
    ingestion_role        = aws_iam_role.rds_s3_import.arn
  }

  depends_on = [
    aws_iam_role_policy_attachment.rds_s3_import,
    aws_s3_bucket_public_access_block.mysql_backup,
    aws_s3_bucket_versioning.mysql_backup
  ]

  tags = {
    Name = "mysql-restored-from-s3"
  }
}

output "s3_backup_bucket_name" {
  description = "S3 bucket where the MySQL backup files must be uploaded."
  value       = aws_s3_bucket.mysql_backup.bucket
}

output "s3_backup_prefix" {
  description = "S3 prefix expected to contain the MySQL backup files."
  value       = var.s3_import_prefix
}

output "rds_endpoint" {
  description = "Endpoint of the restored RDS MySQL database."
  value       = aws_db_instance.restored_from_s3.endpoint
}

output "rds_port" {
  description = "Port of the restored RDS MySQL database."
  value       = aws_db_instance.restored_from_s3.port
}

output "rds_database_name" {
  description = "Name of the restored database."
  value       = aws_db_instance.restored_from_s3.db_name
}
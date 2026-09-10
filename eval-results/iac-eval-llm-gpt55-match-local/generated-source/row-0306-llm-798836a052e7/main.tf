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
  description = "AWS region where resources will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "backup_retention_days" {
  description = "Number of days to retain EC2 backups."
  type        = number
  default     = 30
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
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

resource "aws_security_group" "ec2_sg" {
  name        = "daily-backup-ec2-sg"
  description = "Security group for EC2 instance backed up by AWS Backup"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "daily-backup-ec2-sg"
  }
}

resource "aws_instance" "backed_up_ec2" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.ec2_sg.id]

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name   = "daily-backed-up-ec2"
    Backup = "DailyMidnight"
  }
}

resource "aws_backup_vault" "ec2_backup_vault" {
  name = "ec2-daily-midnight-backup-vault"

  tags = {
    Name = "ec2-daily-midnight-backup-vault"
  }
}

resource "aws_iam_role" "aws_backup_role" {
  name = "aws-backup-ec2-daily-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "aws-backup-ec2-daily-backup-role"
  }
}

resource "aws_iam_role_policy_attachment" "aws_backup_service_role_policy_backup" {
  role       = aws_iam_role.aws_backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "aws_backup_service_role_policy_restore" {
  role       = aws_iam_role.aws_backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_backup_plan" "ec2_daily_midnight_backup_plan" {
  name = "ec2-daily-midnight-backup-plan"

  rule {
    rule_name         = "daily-midnight-ec2-backup"
    target_vault_name = aws_backup_vault.ec2_backup_vault.name

    schedule = "cron(0 0 * * ? *)"

    lifecycle {
      delete_after = var.backup_retention_days
    }

    recovery_point_tags = {
      BackupFrequency = "Daily"
      BackupTimeUTC   = "Midnight"
    }
  }

  tags = {
    Name = "ec2-daily-midnight-backup-plan"
  }
}

resource "aws_backup_selection" "ec2_backup_selection" {
  name         = "ec2-daily-midnight-backup-selection"
  iam_role_arn = aws_iam_role.aws_backup_role.arn
  plan_id      = aws_backup_plan.ec2_daily_midnight_backup_plan.id

  resources = [
    aws_instance.backed_up_ec2.arn
  ]
}

output "ec2_instance_id" {
  description = "ID of the EC2 instance being backed up."
  value       = aws_instance.backed_up_ec2.id
}

output "ec2_instance_arn" {
  description = "ARN of the EC2 instance selected for AWS Backup."
  value       = aws_instance.backed_up_ec2.arn
}

output "backup_vault_name" {
  description = "Name of the AWS Backup vault."
  value       = aws_backup_vault.ec2_backup_vault.name
}

output "backup_plan_id" {
  description = "ID of the AWS Backup plan."
  value       = aws_backup_plan.ec2_daily_midnight_backup_plan.id
}
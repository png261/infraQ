terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

provider "tls" {}

variable "aws_region" {
  description = "AWS region to deploy resources into."
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

resource "tls_private_key" "ec2_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "ec2_key_pair" {
  key_name   = "daily-backup-ec2-key"
  public_key = tls_private_key.ec2_key.public_key_openssh
}

resource "aws_security_group" "ec2_security_group" {
  name        = "daily-backup-ec2-sg"
  description = "Security group for EC2 instance backed up daily"
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

resource "aws_instance" "backup_target" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.ec2_key_pair.key_name
  vpc_security_group_ids = [aws_security_group.ec2_security_group.id]

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "daily-backup-ec2-instance"
  }
}

resource "aws_backup_vault" "ec2_backup_vault" {
  name = "daily-ec2-backup-vault"

  tags = {
    Name = "daily-ec2-backup-vault"
  }
}

resource "aws_backup_plan" "daily_midnight_backup_plan" {
  name = "daily-midnight-ec2-backup-plan"

  rule {
    rule_name         = "daily-midnight-backup"
    target_vault_name = aws_backup_vault.ec2_backup_vault.name
    schedule          = "cron(0 0 * * ? *)"

    lifecycle {
      delete_after = var.backup_retention_days
    }
  }

  tags = {
    Name = "daily-midnight-ec2-backup-plan"
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

resource "aws_iam_role_policy_attachment" "aws_backup_service_role_policy_for_backup" {
  role       = aws_iam_role.aws_backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_selection" "ec2_backup_selection" {
  name         = "daily-midnight-ec2-backup-selection"
  iam_role_arn = aws_iam_role.aws_backup_role.arn
  plan_id      = aws_backup_plan.daily_midnight_backup_plan.id

  resources = [
    aws_instance.backup_target.arn
  ]

  depends_on = [
    aws_iam_role_policy_attachment.aws_backup_service_role_policy_for_backup
  ]
}

output "ec2_instance_id" {
  description = "ID of the EC2 instance being backed up."
  value       = aws_instance.backup_target.id
}

output "ec2_instance_arn" {
  description = "ARN of the EC2 instance assigned to AWS Backup."
  value       = aws_instance.backup_target.arn
}

output "backup_vault_name" {
  description = "Name of the AWS Backup vault."
  value       = aws_backup_vault.ec2_backup_vault.name
}

output "backup_plan_id" {
  description = "ID of the AWS Backup plan."
  value       = aws_backup_plan.daily_midnight_backup_plan.id
}

output "private_key_pem" {
  description = "Private key for connecting to the EC2 instance. Store this securely."
  value       = tls_private_key.ec2_key.private_key_pem
  sensitive   = true
}
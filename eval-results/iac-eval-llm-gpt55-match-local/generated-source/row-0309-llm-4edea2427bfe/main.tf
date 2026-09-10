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
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "key_pair_name" {
  description = "Name of the EC2 key pair."
  type        = string
  default     = "amazon-linux-2023-key"
}

variable "instance_name" {
  description = "Name tag for the EC2 instance."
  type        = string
  default     = "amazon-linux-2023-instance"
}

variable "backup_vault_name" {
  description = "Name of the AWS Backup vault."
  type        = string
  default     = "ec2-backup-vault"
}

variable "backup_plan_name" {
  description = "Name of the AWS Backup plan."
  type        = string
  default     = "daily-ec2-backup-plan"
}

data "aws_ami" "amazon_linux_2023_x86_64" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_key_pair" "ec2_key_pair" {
  key_name   = var.key_pair_name
  public_key = file("./key.pub")
}

resource "aws_instance" "amazon_linux_2023" {
  ami           = data.aws_ami.amazon_linux_2023_x86_64.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.ec2_key_pair.key_name

  tags = {
    Name = var.instance_name
  }
}

resource "aws_backup_vault" "ec2_backup_vault" {
  name = var.backup_vault_name
}

resource "aws_backup_plan" "ec2_backup_plan" {
  name = var.backup_plan_name

  rule {
    rule_name         = "daily-midnight-backup"
    target_vault_name = aws_backup_vault.ec2_backup_vault.name
    schedule          = "cron(0 0 * * ? *)"

    lifecycle {
      delete_after = 7
    }
  }

  advanced_backup_setting {
    resource_type = "EC2"

    backup_options = {
      WindowsVSS = "disabled"
    }
  }
}

resource "aws_iam_role" "aws_backup_role" {
  name = "aws-backup-ec2-selection-role"

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
}

resource "aws_iam_role_policy_attachment" "aws_backup_service_role_policy" {
  role       = aws_iam_role.aws_backup_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_selection" "ec2_backup_selection" {
  name         = "ec2-instance-backup-selection"
  iam_role_arn = aws_iam_role.aws_backup_role.arn
  plan_id      = aws_backup_plan.ec2_backup_plan.id

  resources = [
    aws_instance.amazon_linux_2023.arn
  ]

  depends_on = [
    aws_iam_role_policy_attachment.aws_backup_service_role_policy
  ]
}

output "ec2_instance_id" {
  description = "ID of the created EC2 instance."
  value       = aws_instance.amazon_linux_2023.id
}

output "ec2_instance_arn" {
  description = "ARN of the created EC2 instance."
  value       = aws_instance.amazon_linux_2023.arn
}

output "backup_vault_name" {
  description = "Name of the AWS Backup vault."
  value       = aws_backup_vault.ec2_backup_vault.name
}

output "backup_plan_id" {
  description = "ID of the AWS Backup plan."
  value       = aws_backup_plan.ec2_backup_plan.id
}
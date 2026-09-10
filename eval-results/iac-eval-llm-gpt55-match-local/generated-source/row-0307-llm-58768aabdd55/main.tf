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

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "ec2-daily-backup"
}

variable "instance_type" {
  description = "EC2 instance type."
  type        = string
  default     = "t3.micro"
}

variable "backup_retention_days" {
  description = "Number of days to retain backups."
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

resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.20.1.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.project_name}-public-subnet"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-public-route-table"
  }
}

resource "aws_route" "internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Security group for EC2 instance"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-ec2-sg"
  }
}

resource "aws_instance" "app" {
  ami                    = data.aws_ami.amazon_linux_2023.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.ec2.id]

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size           = 8
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name   = "${var.project_name}-instance"
    Backup = "DailyMidnight"
  }
}

resource "aws_backup_vault" "main" {
  name = "${var.project_name}-vault"

  tags = {
    Name = "${var.project_name}-vault"
  }
}

resource "aws_iam_role" "backup" {
  name = "${var.project_name}-backup-role"

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
    Name = "${var.project_name}-backup-role"
  }
}

resource "aws_iam_role_policy_attachment" "backup_service_role_policy" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_plan" "daily_midnight" {
  name = "${var.project_name}-daily-midnight-plan"

  rule {
    rule_name         = "daily-midnight-backup"
    target_vault_name = aws_backup_vault.main.name

    /*
      Runs every day at midnight UTC.
      AWS Backup cron format:
      cron(Minutes Hours Day-of-month Month Day-of-week Year)
    */
    schedule = "cron(0 0 * * ? *)"

    start_window      = 60
    completion_window = 180

    lifecycle {
      delete_after = var.backup_retention_days
    }

    recovery_point_tags = {
      CreatedBy = "AWS Backup"
      Schedule  = "DailyMidnightUTC"
    }
  }

  tags = {
    Name = "${var.project_name}-daily-midnight-plan"
  }
}

resource "aws_backup_selection" "ec2_instance" {
  name         = "${var.project_name}-ec2-selection"
  iam_role_arn = aws_iam_role.backup.arn
  plan_id      = aws_backup_plan.daily_midnight.id

  resources = [
    aws_instance.app.arn
  ]

  depends_on = [
    aws_iam_role_policy_attachment.backup_service_role_policy
  ]
}

output "ec2_instance_id" {
  description = "ID of the EC2 instance protected by AWS Backup."
  value       = aws_instance.app.id
}

output "ec2_instance_arn" {
  description = "ARN of the EC2 instance protected by AWS Backup."
  value       = aws_instance.app.arn
}

output "backup_vault_name" {
  description = "Name of the AWS Backup vault."
  value       = aws_backup_vault.main.name
}

output "backup_plan_id" {
  description = "ID of the AWS Backup plan."
  value       = aws_backup_plan.daily_midnight.id
}
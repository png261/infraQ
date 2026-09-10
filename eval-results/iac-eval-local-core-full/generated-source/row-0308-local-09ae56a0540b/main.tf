data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_iam_policy_document" "backup_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["backup.amazonaws.com"]
    }
  }
}

resource "aws_key_pair" "ec2" {
  key_name   = "daily-backup-benchmark-key"
  public_key = var.public_key
}

resource "aws_instance" "ec2" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type
  key_name      = aws_key_pair.ec2.key_name

  tags = {
    Name = "daily-backup-benchmark-instance"
  }
}

resource "aws_backup_vault" "ec2" {
  name = "daily-backup-benchmark-vault"
}

resource "aws_backup_plan" "ec2" {
  name = "daily-backup-benchmark-plan"

  rule {
    rule_name         = "daily-midnight-backup"
    target_vault_name = aws_backup_vault.ec2.name
    schedule          = "cron(0 0 * * ? *)"
  }

  advanced_backup_setting {
    resource_type = "EC2"

    backup_options = {
      WindowsVSS = "enabled"
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "daily-backup-benchmark-role"
  assume_role_policy = data.aws_iam_policy_document.backup_assume_role.json
}

resource "aws_iam_role_policy_attachment" "backup_service_role" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_selection" "ec2" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "daily-backup-benchmark-selection"
  plan_id      = aws_backup_plan.ec2.id
  resources    = [aws_instance.ec2.arn]
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
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

resource "aws_iam_role" "backup" {
  name               = "daily-ec2-backup-role"
  assume_role_policy = data.aws_iam_policy_document.backup_assume_role.json
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_instance" "example" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  tags = {
    Name = "daily-backup-example"
  }
}

resource "aws_backup_vault" "example" {
  name = "daily-ec2-backup-vault"
}

resource "aws_backup_plan" "example" {
  name = "daily-ec2-backup-plan"

  rule {
    rule_name         = "daily-midnight-backup"
    target_vault_name = aws_backup_vault.example.name
    schedule          = "cron(0 0 * * ? *)"
  }

  advanced_backup_setting {
    resource_type = "EC2"

    backup_options = {
      WindowsVSS = "enabled"
    }
  }
}

resource "aws_backup_selection" "example" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "daily-ec2-backup-selection"
  plan_id      = aws_backup_plan.example.id
  resources    = [aws_instance.example.arn]
}

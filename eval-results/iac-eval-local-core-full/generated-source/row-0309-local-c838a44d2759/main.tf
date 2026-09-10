data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
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

resource "aws_key_pair" "example" {
  key_name   = "example-backup-key"
  public_key = file("./key.pub")
}

resource "aws_instance" "example" {
  ami           = data.aws_ami.amazon_linux_2023.id
  instance_type = "t2.micro"
  key_name      = aws_key_pair.example.key_name
}

resource "aws_backup_vault" "example" {
  name = "example-backup-vault"
}

resource "aws_backup_plan" "example" {
  name = "example-backup-plan"

  rule {
    rule_name         = "daily-midnight"
    target_vault_name = aws_backup_vault.example.name
    schedule          = "cron(0 0 * * ? *)"

    lifecycle {
      delete_after = 7
    }
  }

  advanced_backup_setting {
    resource_type = "EC2"

    backup_options = {
      WindowsVSS = "enabled"
    }
  }
}

resource "aws_iam_role" "backup" {
  name               = "example-backup-role"
  assume_role_policy = data.aws_iam_policy_document.backup_assume_role.json
}

resource "aws_iam_role_policy_attachment" "backup" {
  role       = aws_iam_role.backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_backup_selection" "example" {
  iam_role_arn = aws_iam_role.backup.arn
  name         = "example-backup-selection"
  plan_id      = aws_backup_plan.example.id
  resources    = [aws_instance.example.arn]
}

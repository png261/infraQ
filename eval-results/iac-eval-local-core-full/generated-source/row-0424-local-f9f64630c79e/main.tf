resource "aws_efs_file_system" "this" {
  creation_token = "iac-eval-efs-backup-enabled"

  tags = {
    Name = "iac-eval-efs-backup-enabled"
  }
}

resource "aws_efs_backup_policy" "this" {
  file_system_id = aws_efs_file_system.this.id

  backup_policy {
    status = "ENABLED"
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_glacier_vault" "long_term_backup" {
  name = "long-term-backup-vault"
}

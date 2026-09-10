data "aws_caller_identity" "current" {}

locals {
  bucket_name = "iac-eval-versioning-disabled-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Disabled"
  }
}

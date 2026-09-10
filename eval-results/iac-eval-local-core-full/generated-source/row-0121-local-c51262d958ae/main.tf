resource "aws_s3_bucket" "source" {
  bucket = "iac-eval-source-bucket-20260518"
}

resource "aws_s3_bucket" "logs" {
  bucket = "iac-eval-logs-bucket-20260518"
}

resource "aws_s3_bucket_ownership_controls" "source" {
  bucket = aws_s3_bucket.source.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "source_private" {
  bucket = aws_s3_bucket.source.id
  acl    = "private"

  depends_on = [aws_s3_bucket_ownership_controls.source]
}

resource "aws_s3_bucket_acl" "logs_delivery_write" {
  bucket = aws_s3_bucket.logs.id
  acl    = "log-delivery-write"

  depends_on = [aws_s3_bucket_ownership_controls.logs]
}

resource "aws_s3_bucket_logging" "source_to_logs" {
  bucket        = aws_s3_bucket.source.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "source-access-logs/"

  depends_on = [aws_s3_bucket_acl.logs_delivery_write]
}

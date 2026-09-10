resource "aws_s3_bucket" "source" {
  bucket = "${var.bucket_name_prefix}-source"
}

resource "aws_s3_bucket" "logs" {
  bucket = "${var.bucket_name_prefix}-logs"
}

resource "aws_s3_bucket_logging" "source" {
  bucket = aws_s3_bucket.source.id

  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "log/"
}

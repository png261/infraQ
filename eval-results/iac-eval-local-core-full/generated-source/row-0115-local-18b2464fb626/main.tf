locals {
  cloudgoat_bucket_name = "cloudgoat-data-storage-${var.bucket_suffix}"
  web_bucket_name       = "cloudgoat-web-data-storage-${var.bucket_suffix}"
}

resource "aws_s3_bucket" "cloudgoat_data" {
  bucket = local.cloudgoat_bucket_name
}

resource "aws_s3_bucket_ownership_controls" "cloudgoat_data" {
  bucket = aws_s3_bucket.cloudgoat_data.id

  rule {
    object_ownership = "ObjectWriter"
  }
}

resource "aws_s3_bucket_acl" "cloudgoat_data" {
  bucket = aws_s3_bucket.cloudgoat_data.id
  acl    = "private"

  depends_on = [aws_s3_bucket_ownership_controls.cloudgoat_data]
}

resource "aws_s3_bucket" "web_data" {
  bucket = local.web_bucket_name
}

resource "aws_s3_object" "order_data" {
  bucket = aws_s3_bucket.web_data.id
  key    = "order_data2.csv"
  source = "${path.module}/order_data2.csv"
}

resource "aws_s3_bucket_public_access_block" "web_data" {
  bucket = aws_s3_bucket.web_data.id

  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "web_data_put_object" {
  bucket = aws_s3_bucket.web_data.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowPublicPutObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.web_data.arn}/*"
      }
    ]
  })
}

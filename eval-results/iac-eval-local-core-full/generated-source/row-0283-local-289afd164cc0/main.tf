resource "aws_s3_bucket" "website_cors" {
  bucket_prefix = "domain-cors-"
}

resource "aws_s3_bucket_cors_configuration" "website" {
  bucket = aws_s3_bucket.website_cors.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "POST"]
    allowed_origins = ["https://domain.com"]
  }
}

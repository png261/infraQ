resource "aws_s3_bucket" "static_website" {
  bucket_prefix = "static-website-"
}

resource "aws_s3_bucket_website_configuration" "static_website" {
  bucket = aws_s3_bucket.static_website.id

  index_document {
    suffix = "index.html"
  }
}

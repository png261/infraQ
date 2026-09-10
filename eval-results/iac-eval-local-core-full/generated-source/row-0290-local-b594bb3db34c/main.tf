resource "aws_s3_bucket" "example" {
  bucket_prefix = "iac-eval-example-"
}

resource "aws_s3_bucket_versioning" "example" {
  bucket = aws_s3_bucket.example.id

  versioning_configuration {
    status = "Enabled"
  }
}

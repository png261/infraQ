resource "aws_s3_bucket" "this" {
  bucket = "mybucket"
}

resource "aws_s3_bucket_metric" "this" {
  bucket = aws_s3_bucket.this.id
  name   = "EntireBucket"
}

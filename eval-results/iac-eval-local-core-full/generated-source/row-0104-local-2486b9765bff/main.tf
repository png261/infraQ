resource "aws_s3_bucket" "my_bucket" {
  bucket = "my-bucket"
}

resource "aws_s3_bucket_policy" "my_bucket" {
  bucket = aws_s3_bucket.my_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "DenySpecificIPAddress"
    Statement = [
      {
        Sid       = "DenyRequestsFromSpecificIP"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.my_bucket.arn,
          "${aws_s3_bucket.my_bucket.arn}/*"
        ]
        Condition = {
          IpAddress = {
            "aws:SourceIp" = "203.0.113.0/32"
          }
        }
      }
    ]
  })
}

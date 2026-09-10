output "bucket_name" {
  description = "Name of the S3 bucket configured with CORS."
  value       = aws_s3_bucket.website_cors.id
}

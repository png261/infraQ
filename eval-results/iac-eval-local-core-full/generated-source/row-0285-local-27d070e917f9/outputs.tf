output "bucket_name" {
  description = "Name of the S3 bucket configured for static website hosting."
  value       = aws_s3_bucket.static_website.id
}

output "website_endpoint" {
  description = "S3 static website endpoint for the bucket."
  value       = aws_s3_bucket_website_configuration.static_website.website_endpoint
}

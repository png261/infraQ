output "bucket_name" {
  description = "Name of the S3 bucket configured for website hosting."
  value       = aws_s3_bucket.website.id
}

output "website_endpoint" {
  description = "S3 static website endpoint for the bucket."
  value       = aws_s3_bucket_website_configuration.website.website_endpoint
}

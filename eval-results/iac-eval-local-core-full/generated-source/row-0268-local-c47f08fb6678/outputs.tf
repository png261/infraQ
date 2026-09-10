output "website_images_bucket_name" {
  description = "Name of the S3 bucket for website images."
  value       = aws_s3_bucket.website_images.id
}

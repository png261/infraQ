output "bucket_name" {
  description = "Name of the S3 bucket used for video content."
  value       = aws_s3_bucket.video_content.bucket
}

output "cloudfront_distribution_domain_name" {
  description = "CloudFront distribution domain name for video streaming content."
  value       = aws_cloudfront_distribution.video_content.domain_name
}

output "route53_record_fqdn" {
  description = "Fully qualified Route53 record name that aliases to CloudFront."
  value       = aws_route53_record.video.fqdn
}

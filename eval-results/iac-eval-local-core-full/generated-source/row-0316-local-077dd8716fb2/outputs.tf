output "s3_bucket_name" {
  description = "Name of the S3 bucket storing video content."
  value       = aws_s3_bucket.video_content.bucket
}

output "cloudfront_distribution_domain_name" {
  description = "CloudFront distribution domain name for global video delivery."
  value       = aws_cloudfront_distribution.video_cdn.domain_name
}

output "route53_record_fqdn" {
  description = "Route53 record pointing to the CloudFront distribution."
  value       = aws_route53_record.video.fqdn
}

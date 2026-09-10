output "cloudfront_distribution_domain_name" {
  description = "CloudFront distribution domain name for the video streaming site."
  value       = aws_cloudfront_distribution.video_distribution.domain_name
}

output "route53_zone_name_servers" {
  description = "Name servers for the created Route53 hosted zone."
  value       = aws_route53_zone.video_site.name_servers
}

variable "domain_name" {
  description = "Domain name for the Route53 hosted zone used by the video site. The default is documentation-only and should be changed before a real deployment."
  type        = string
  default     = "example.com"
}

variable "record_name" {
  description = "Subdomain record name for the CloudFront distribution."
  type        = string
  default     = "video"
}

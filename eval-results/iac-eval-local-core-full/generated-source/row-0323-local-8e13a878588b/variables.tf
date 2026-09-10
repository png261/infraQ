variable "lb_certificate_arn" {
  description = "ARN of an existing ACM certificate in us-east-1 for the HTTPS load balancer listener."
  type        = string
  default     = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
}

variable "certificate_arn" {
  description = "ARN of an existing AWS Certificate Manager certificate in us-east-1 for the HTTPS ALB listener."
  type        = string

  validation {
    condition     = can(regex("^arn:aws[a-zA-Z-]*:acm:us-east-1:[0-9]{12}:certificate/.+", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN in us-east-1."
  }
}

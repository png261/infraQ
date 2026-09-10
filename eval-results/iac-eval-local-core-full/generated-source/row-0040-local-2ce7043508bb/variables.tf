variable "artifact_bucket_name" {
  description = "Optional globally unique S3 bucket name for CodeBuild artifacts. Defaults to an account-scoped name."
  type        = string
  default     = null
}

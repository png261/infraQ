variable "project_name" {
  description = "Name for the CodeBuild autograder project and related IAM resources."
  type        = string
  default     = "cs-autograder"
}

variable "github_repository_url" {
  description = "HTTPS clone URL of the GitHub repository containing the autograder source and buildspec.yml."
  type        = string
  default     = "https://github.com/example/cs-autograder.git"
}

variable "results_bucket_name" {
  description = "Globally unique S3 bucket name used to store CodeBuild autograder artifacts and results."
  type        = string
  default     = "cs-autograder-results-example"
}

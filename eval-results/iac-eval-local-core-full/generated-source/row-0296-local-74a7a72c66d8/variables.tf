variable "project_name" {
  description = "Name of the AWS CodeBuild project for the CS autograder."
  type        = string
  default     = "cs-autograder"
}

variable "github_repository_url" {
  description = "HTTPS URL of the GitHub repository containing the autograder or student code source."
  type        = string
  default     = "https://github.com/example/cs-autograder.git"
}

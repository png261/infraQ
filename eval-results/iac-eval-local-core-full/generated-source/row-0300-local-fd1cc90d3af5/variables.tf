variable "project_name" {
  description = "Name prefix for the autograder infrastructure."
  type        = string
  default     = "cs-autograder"
}

variable "github_repo_url" {
  description = "HTTPS URL of the GitHub repository containing the autograder/student code source."
  type        = string
  default     = "https://github.com/example/cs-autograder.git"
}

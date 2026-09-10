variable "github_source_location" {
  description = "HTTPS GitHub repository URL containing autograder source/buildspec. CodeBuild retrieves this before starting the VPC-isolated build runtime."
  type        = string
  default     = "https://github.com/example-org/example-autograder.git"
}

variable "project_name" {
  description = "Name prefix for the autograder infrastructure."
  type        = string
  default     = "cs-autograder"
}

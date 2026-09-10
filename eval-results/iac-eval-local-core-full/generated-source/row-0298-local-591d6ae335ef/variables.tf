variable "project_name" {
  description = "Name prefix for the autograder infrastructure."
  type        = string
  default     = "cs-autograder"
}

variable "github_repository_url" {
  description = "HTTPS URL of the GitHub repository containing the autograder source. Configure CodeBuild credentials outside Terraform if the repository is private."
  type        = string
  default     = "https://github.com/example/cs-autograder.git"
}

variable "vpc_cidr_block" {
  description = "CIDR block for the isolated autograder VPC."
  type        = string
  default     = "10.40.0.0/16"
}

variable "subnet_cidr_block" {
  description = "CIDR block for the isolated CodeBuild subnet."
  type        = string
  default     = "10.40.1.0/24"
}

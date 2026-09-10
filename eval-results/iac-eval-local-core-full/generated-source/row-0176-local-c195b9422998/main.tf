provider "aws" {
  region = "us-east-1"
}

resource "aws_sagemaker_code_repository" "terraform_provider_aws" {
  code_repository_name = "terraform-provider-aws"

  git_config {
    repository_url = "https://github.com/hashicorp/terraform-provider-aws.git"
  }
}

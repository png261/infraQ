terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_sagemaker_code_repository" "terraform_provider_aws" {
  code_repository_name = "terraform-provider-aws-repository"

  git_config {
    repository_url = "https://github.com/hashicorp/terraform-provider-aws.git"
  }
}

output "sagemaker_code_repository_name" {
  value = aws_sagemaker_code_repository.terraform_provider_aws.code_repository_name
}

output "sagemaker_code_repository_url" {
  value = aws_sagemaker_code_repository.terraform_provider_aws.git_config[0].repository_url
}
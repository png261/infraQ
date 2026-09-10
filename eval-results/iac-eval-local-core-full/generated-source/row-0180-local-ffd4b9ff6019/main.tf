data "aws_iam_policy_document" "sagemaker_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_sagemaker_prebuilt_ecr_image" "notebook_base" {
  repository_name = "sagemaker-scikit-learn"
  image_tag       = "0.23-1-cpu-py3"
}

resource "aws_iam_role" "sagemaker_notebook" {
  name               = "sagemaker-notebook-iac-eval"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role.json

  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess",
  ]
}

resource "aws_sagemaker_code_repository" "terraform_provider_aws" {
  code_repository_name = "terraform-provider-aws"

  git_config {
    repository_url = "https://github.com/hashicorp/terraform-provider-aws.git"
  }
}

resource "aws_sagemaker_notebook_instance" "this" {
  name                    = "terraform-provider-aws-notebook"
  role_arn                = aws_iam_role.sagemaker_notebook.arn
  instance_type           = "ml.t3.medium"
  default_code_repository = aws_sagemaker_code_repository.terraform_provider_aws.code_repository_name

  tags = {
    Environment = "dev"
    Benchmark   = "iac-eval"
  }
}

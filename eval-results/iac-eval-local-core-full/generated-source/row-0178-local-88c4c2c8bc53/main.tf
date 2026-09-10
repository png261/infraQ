terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

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

resource "aws_iam_role" "sagemaker_execution" {
  name               = "iac-eval-sagemaker-kmeans-execution-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role.json
}

data "aws_sagemaker_prebuilt_ecr_image" "kmeans" {
  repository_name = "kmeans"
  image_tag       = "1"
}

resource "aws_sagemaker_model" "kmeans" {
  name               = "iac-eval-kmeans-model"
  execution_role_arn = aws_iam_role.sagemaker_execution.arn

  primary_container {
    image = data.aws_sagemaker_prebuilt_ecr_image.kmeans.registry_path
  }
}

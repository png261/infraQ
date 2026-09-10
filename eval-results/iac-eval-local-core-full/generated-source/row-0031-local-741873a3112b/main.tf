terraform {
  required_version = ">= 1.5.0"

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

data "aws_iam_policy_document" "elastic_beanstalk_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["elasticbeanstalk.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "elastic_beanstalk_service" {
  name               = "iac-eval-elastic-beanstalk-service-role"
  assume_role_policy = data.aws_iam_policy_document.elastic_beanstalk_assume_role.json
}

resource "aws_elastic_beanstalk_application" "example" {
  name        = "iac-eval-elastic-beanstalk-app"
  description = "Minimal Elastic Beanstalk application for IaC-Eval benchmark."

  appversion_lifecycle {
    service_role          = aws_iam_role.elastic_beanstalk_service.arn
    max_count             = 10
    delete_source_from_s3 = true
  }
}

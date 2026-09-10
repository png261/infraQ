terraform {
  required_version = ">= 1.0"

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

resource "aws_elastic_beanstalk_application" "example" {
  name = "example-elastic-beanstalk-application"

  appversion_lifecycle {
    service_role          = aws_iam_role.elastic_beanstalk_service.arn
    max_age_in_days       = 5
    delete_source_from_s3 = true
  }
}

resource "aws_iam_role" "elastic_beanstalk_service" {
  name = "example-elastic-beanstalk-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "elasticbeanstalk.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

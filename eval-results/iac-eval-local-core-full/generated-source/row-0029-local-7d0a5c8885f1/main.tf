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

resource "aws_elastic_beanstalk_application" "go_app" {
  name = "go-elastic-beanstalk-app"
}

resource "aws_elastic_beanstalk_configuration_template" "go_template" {
  name                = "go-elastic-beanstalk-template"
  application         = aws_elastic_beanstalk_application.go_app.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.6.1 running Go 1"
}

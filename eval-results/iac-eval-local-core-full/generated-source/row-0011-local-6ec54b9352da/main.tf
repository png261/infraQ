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

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_elastic_beanstalk_solution_stack" "docker" {
  most_recent = true
  name_regex  = "^64bit Amazon Linux .* running Docker$"
}

resource "aws_iam_role" "eb_ec2_role" {
  name = "eb_ec2_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eb_web_tier" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_instance_profile" "eb_ec2_profile" {
  name = "eb_ec2_profile"
  role = aws_iam_role.eb_ec2_role.name
}

resource "aws_elastic_beanstalk_application" "myapp" {
  name = "myapp"
}

resource "aws_s3_bucket" "app_versions" {
  bucket = "eb-myapp-version-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
}

resource "aws_s3_object" "examplebucket_object" {
  bucket = aws_s3_bucket.app_versions.bucket
  key    = "Dockerrun.aws.json"
  source = "${path.module}/Dockerrun.aws.json"
}

resource "aws_elastic_beanstalk_application_version" "version" {
  name        = "version"
  application = aws_elastic_beanstalk_application.myapp.name
  bucket      = aws_s3_object.examplebucket_object.bucket
  key         = aws_s3_object.examplebucket_object.key
}

resource "aws_elastic_beanstalk_environment" "eb_env" {
  name                = "eb-env"
  application         = aws_elastic_beanstalk_application.myapp.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.docker.name
  version_label       = aws_elastic_beanstalk_application_version.version.name

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_ec2_profile.name
  }
}

resource "aws_route53_zone" "main" {
  name = "main.example.com"
}

resource "aws_route53_record" "eb_env" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "app.${aws_route53_zone.main.name}"
  type    = "CNAME"
  ttl     = 300
  records = [aws_elastic_beanstalk_environment.eb_env.cname]
}

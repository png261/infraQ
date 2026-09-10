terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the Elastic Beanstalk application will be created."
  type        = string
  default     = "us-east-1"
}

variable "application_name" {
  description = "Name of the Elastic Beanstalk application."
  type        = string
  default     = "example-elastic-beanstalk-app"
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_iam_role" "elastic_beanstalk_service_role" {
  name = "elastic-beanstalk-service-role-${random_id.suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "elasticbeanstalk.amazonaws.com"
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "elasticbeanstalk"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_service_policy" {
  role       = aws_iam_role.elastic_beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkService"
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_enhanced_health_policy" {
  role       = aws_iam_role.elastic_beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_elastic_beanstalk_application" "app" {
  name        = var.application_name
  description = "Elastic Beanstalk application with application version lifecycle policy."

  appversion_lifecycle {
    service_role          = aws_iam_role.elastic_beanstalk_service_role.arn
    max_age_in_days       = 5
    delete_source_from_s3 = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.elastic_beanstalk_service_policy,
    aws_iam_role_policy_attachment.elastic_beanstalk_enhanced_health_policy
  ]
}

output "elastic_beanstalk_application_name" {
  description = "Name of the Elastic Beanstalk application."
  value       = aws_elastic_beanstalk_application.app.name
}

output "elastic_beanstalk_service_role_arn" {
  description = "ARN of the Elastic Beanstalk service role used for application version lifecycle management."
  value       = aws_iam_role.elastic_beanstalk_service_role.arn
}
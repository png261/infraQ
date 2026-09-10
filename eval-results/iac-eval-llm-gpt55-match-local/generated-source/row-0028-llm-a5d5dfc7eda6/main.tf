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
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the Elastic Beanstalk application template will be created."
  type        = string
  default     = "us-east-1"
}

variable "application_name" {
  description = "Name of the Elastic Beanstalk application."
  type        = string
  default     = "example-elastic-beanstalk-app"
}

variable "configuration_template_name" {
  description = "Name of the Elastic Beanstalk configuration template."
  type        = string
  default     = "example-elastic-beanstalk-template"
}

variable "solution_stack_name" {
  description = "Elastic Beanstalk solution stack to use for the configuration template."
  type        = string
  default     = "64bit Amazon Linux 2023 v6.5.2 running Node.js 20"
}

variable "instance_type" {
  description = "EC2 instance type for Elastic Beanstalk environments created from this template."
  type        = string
  default     = "t3.micro"
}

resource "aws_elastic_beanstalk_application" "app" {
  name        = var.application_name
  description = "Example Elastic Beanstalk application created by Terraform."
}

resource "aws_iam_role" "elastic_beanstalk_service_role" {
  name = "${var.application_name}-eb-service-role"

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

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_service_role_enhanced_health" {
  role       = aws_iam_role.elastic_beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_service_role_managed_updates" {
  role       = aws_iam_role.elastic_beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy"
}

resource "aws_iam_role" "elastic_beanstalk_ec2_role" {
  name = "${var.application_name}-eb-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_ec2_web_tier" {
  role       = aws_iam_role.elastic_beanstalk_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_ec2_worker_tier" {
  role       = aws_iam_role.elastic_beanstalk_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier"
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_ec2_multicontainer_docker" {
  role       = aws_iam_role.elastic_beanstalk_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
}

resource "aws_iam_instance_profile" "elastic_beanstalk_instance_profile" {
  name = "${var.application_name}-eb-instance-profile"
  role = aws_iam_role.elastic_beanstalk_ec2_role.name
}

resource "aws_elastic_beanstalk_configuration_template" "template" {
  name                = var.configuration_template_name
  application         = aws_elastic_beanstalk_application.app.name
  solution_stack_name = var.solution_stack_name

  description = "Reusable Elastic Beanstalk configuration template created by Terraform."

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "SingleInstance"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.elastic_beanstalk_service_role.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.elastic_beanstalk_instance_profile.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = var.instance_type
  }

  setting {
    namespace = "aws:elasticbeanstalk:healthreporting:system"
    name      = "SystemType"
    value     = "enhanced"
  }

  depends_on = [
    aws_iam_role_policy_attachment.elastic_beanstalk_service_role_enhanced_health,
    aws_iam_role_policy_attachment.elastic_beanstalk_service_role_managed_updates,
    aws_iam_role_policy_attachment.elastic_beanstalk_ec2_web_tier,
    aws_iam_role_policy_attachment.elastic_beanstalk_ec2_worker_tier,
    aws_iam_role_policy_attachment.elastic_beanstalk_ec2_multicontainer_docker
  ]
}

output "elastic_beanstalk_application_name" {
  description = "Name of the Elastic Beanstalk application."
  value       = aws_elastic_beanstalk_application.app.name
}

output "elastic_beanstalk_configuration_template_name" {
  description = "Name of the Elastic Beanstalk configuration template."
  value       = aws_elastic_beanstalk_configuration_template.template.name
}

output "elastic_beanstalk_service_role_name" {
  description = "IAM service role used by Elastic Beanstalk."
  value       = aws_iam_role.elastic_beanstalk_service_role.name
}

output "elastic_beanstalk_instance_profile_name" {
  description = "IAM instance profile used by EC2 instances in Elastic Beanstalk."
  value       = aws_iam_instance_profile.elastic_beanstalk_instance_profile.name
}
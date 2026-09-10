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

############################
# Variables
############################

variable "aws_region" {
  description = "AWS region where the Elastic Beanstalk environment will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "application_name" {
  description = "Name of the Elastic Beanstalk application."
  type        = string
  default     = "supported-language-web-app"
}

variable "environment_name" {
  description = "Name of the Elastic Beanstalk environment."
  type        = string
  default     = "supported-language-web-app-env"
}

variable "instance_type" {
  description = "EC2 instance type used by Elastic Beanstalk."
  type        = string
  default     = "t3.micro"
}

variable "min_instances" {
  description = "Minimum number of EC2 instances in the Auto Scaling group."
  type        = number
  default     = 1
}

variable "max_instances" {
  description = "Maximum number of EC2 instances in the Auto Scaling group."
  type        = number
  default     = 3
}

############################
# Data Sources
############################

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_elastic_beanstalk_solution_stack" "python" {
  most_recent = true
  name_regex  = "^64bit Amazon Linux .* running Python .*"
}

############################
# IAM Role for Elastic Beanstalk Service
############################

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

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_enhanced_health" {
  role       = aws_iam_role.elastic_beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_managed_updates" {
  role       = aws_iam_role.elastic_beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy"
}

############################
# IAM Role for EC2 Instances
############################

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

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_web_tier" {
  role       = aws_iam_role.elastic_beanstalk_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_worker_tier" {
  role       = aws_iam_role.elastic_beanstalk_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier"
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_multicontainer_docker" {
  role       = aws_iam_role.elastic_beanstalk_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
}

resource "aws_iam_instance_profile" "elastic_beanstalk_instance_profile" {
  name = "${var.application_name}-eb-instance-profile"
  role = aws_iam_role.elastic_beanstalk_ec2_role.name
}

############################
# Elastic Beanstalk Application
############################

resource "aws_elastic_beanstalk_application" "web_app" {
  name        = var.application_name
  description = "Elastic Beanstalk application for a scalable web application using a supported programming language."

  appversion_lifecycle {
    service_role          = aws_iam_role.elastic_beanstalk_service_role.arn
    max_count             = 10
    delete_source_from_s3 = true
  }
}

############################
# Elastic Beanstalk Environment
############################

resource "aws_elastic_beanstalk_environment" "web_app_env" {
  name                = var.environment_name
  application         = aws_elastic_beanstalk_application.web_app.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.python.name
  tier                = "WebServer"

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "LoadBalanced"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
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
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = tostring(var.min_instances)
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = tostring(var.max_instances)
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = data.aws_vpc.default.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", data.aws_subnets.default.ids)
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = join(",", data.aws_subnets.default.ids)
  }

  setting {
    namespace = "aws:elasticbeanstalk:healthreporting:system"
    name      = "SystemType"
    value     = "enhanced"
  }

  setting {
    namespace = "aws:elasticbeanstalk:command"
    name      = "DeploymentPolicy"
    value     = "Rolling"
  }

  setting {
    namespace = "aws:elasticbeanstalk:command"
    name      = "BatchSizeType"
    value     = "Percentage"
  }

  setting {
    namespace = "aws:elasticbeanstalk:command"
    name      = "BatchSize"
    value     = "50"
  }

  tags = {
    Name        = var.environment_name
    Application = var.application_name
    ManagedBy   = "Terraform"
  }

  depends_on = [
    aws_iam_role_policy_attachment.elastic_beanstalk_enhanced_health,
    aws_iam_role_policy_attachment.elastic_beanstalk_managed_updates,
    aws_iam_role_policy_attachment.elastic_beanstalk_web_tier,
    aws_iam_instance_profile.elastic_beanstalk_instance_profile
  ]
}

############################
# Outputs
############################

output "elastic_beanstalk_application_name" {
  description = "Name of the Elastic Beanstalk application."
  value       = aws_elastic_beanstalk_application.web_app.name
}

output "elastic_beanstalk_environment_name" {
  description = "Name of the Elastic Beanstalk environment."
  value       = aws_elastic_beanstalk_environment.web_app_env.name
}

output "elastic_beanstalk_environment_url" {
  description = "URL of the deployed Elastic Beanstalk environment."
  value       = aws_elastic_beanstalk_environment.web_app_env.endpoint_url
}

output "elastic_beanstalk_solution_stack" {
  description = "Elastic Beanstalk platform used by the environment."
  value       = data.aws_elastic_beanstalk_solution_stack.python.name
}
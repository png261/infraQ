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
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "The root domain name to manage in Route 53."
  type        = string
  default     = "example.com"
}

variable "app_subdomain" {
  description = "Subdomain that points to the Elastic Beanstalk environment."
  type        = string
  default     = "www"
}

variable "db_username" {
  description = "Username for the Elastic Beanstalk connected RDS database."
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "Password for the Elastic Beanstalk connected RDS database."
  type        = string
  sensitive   = true
  default     = "ChangeMe12345!"
}

locals {
  application_name = "myapp"
  environment_name = "myenv"
  instance_profile = "eb_ec2_profile1"
  database_name    = "myapp_db"
  fqdn             = "${var.app_subdomain}.${var.domain_name}"
}

resource "aws_iam_role" "eb_ec2_role" {
  name = "eb_ec2_role1"

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

resource "aws_iam_role_policy_attachment" "eb_ec2_web_tier" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_role_policy_attachment" "eb_ec2_worker_tier" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier"
}

resource "aws_iam_role_policy_attachment" "eb_ec2_multicontainer_docker" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
}

resource "aws_iam_instance_profile" "eb_ec2_profile" {
  name = local.instance_profile
  role = aws_iam_role.eb_ec2_role.name
}

resource "aws_iam_role" "eb_service_role" {
  name = "eb_service_role1"

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

resource "aws_iam_role_policy_attachment" "eb_service_enhanced_health" {
  role       = aws_iam_role.eb_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_iam_role_policy_attachment" "eb_service_managed_updates" {
  role       = aws_iam_role.eb_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy"
}

resource "aws_elastic_beanstalk_application" "app" {
  name        = local.application_name
  description = "Elastic Beanstalk application for ${local.environment_name}"
}

resource "aws_elastic_beanstalk_environment" "env" {
  name                = local.environment_name
  application         = aws_elastic_beanstalk_application.app.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.3.0 running Python 3.11"
  tier                = "WebServer"

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "LoadBalanced"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.eb_service_role.name
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_ec2_profile.name
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = "1"
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = "2"
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = "t3.micro"
  }

  setting {
    namespace = "aws:elasticbeanstalk:healthreporting:system"
    name      = "SystemType"
    value     = "enhanced"
  }

  setting {
    namespace = "aws:rds:dbinstance"
    name      = "DBEngine"
    value     = "mysql"
  }

  setting {
    namespace = "aws:rds:dbinstance"
    name      = "DBEngineVersion"
    value     = "8.0"
  }

  setting {
    namespace = "aws:rds:dbinstance"
    name      = "DBInstanceClass"
    value     = "db.t3.micro"
  }

  setting {
    namespace = "aws:rds:dbinstance"
    name      = "DBAllocatedStorage"
    value     = "20"
  }

  setting {
    namespace = "aws:rds:dbinstance"
    name      = "DBName"
    value     = local.database_name
  }

  setting {
    namespace = "aws:rds:dbinstance"
    name      = "DBUser"
    value     = var.db_username
  }

  setting {
    namespace = "aws:rds:dbinstance"
    name      = "DBPassword"
    value     = var.db_password
  }

  setting {
    namespace = "aws:rds:dbinstance"
    name      = "MultiAZDatabase"
    value     = "false"
  }

  setting {
    namespace = "aws:rds:dbinstance"
    name      = "HasCoupledDatabase"
    value     = "true"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eb_ec2_web_tier,
    aws_iam_role_policy_attachment.eb_ec2_worker_tier,
    aws_iam_role_policy_attachment.eb_ec2_multicontainer_docker,
    aws_iam_role_policy_attachment.eb_service_enhanced_health,
    aws_iam_role_policy_attachment.eb_service_managed_updates
  ]
}

resource "aws_route53_zone" "primary" {
  name = var.domain_name
}

resource "aws_route53_record" "www_to_beanstalk" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = local.fqdn
  type    = "CNAME"
  ttl     = 300
  records = [aws_elastic_beanstalk_environment.env.cname]
}

output "route53_name_servers" {
  description = "Name servers for the Route 53 hosted zone. Configure these at your domain registrar."
  value       = aws_route53_zone.primary.name_servers
}

output "elastic_beanstalk_environment_name" {
  description = "Elastic Beanstalk environment name."
  value       = aws_elastic_beanstalk_environment.env.name
}

output "elastic_beanstalk_cname" {
  description = "Elastic Beanstalk environment CNAME."
  value       = aws_elastic_beanstalk_environment.env.cname
}

output "application_url" {
  description = "DNS name routed through Route 53 to the Elastic Beanstalk environment."
  value       = "http://${aws_route53_record.www_to_beanstalk.fqdn}"
}

output "database_name" {
  description = "Name of the Elastic Beanstalk connected RDS database."
  value       = local.database_name
}

output "instance_profile_name" {
  description = "Elastic Beanstalk EC2 instance profile name."
  value       = aws_iam_instance_profile.eb_ec2_profile.name
}
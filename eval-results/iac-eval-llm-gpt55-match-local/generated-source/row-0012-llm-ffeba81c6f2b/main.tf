terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where resources will be deployed."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Domain name for the Route53 hosted zone."
  type        = string
  default     = "example-bluegreen-deployment.com"
}

variable "application_dns_name" {
  description = "DNS record name used for the application."
  type        = string
  default     = "app"
}

variable "blue_weight" {
  description = "Route53 weighted routing value for the blue environment."
  type        = number
  default     = 90
}

variable "green_weight" {
  description = "Route53 weighted routing value for the green environment."
  type        = number
  default     = 10
}

resource "random_id" "suffix" {
  byte_length = 4
}

data "aws_elastic_beanstalk_solution_stack" "nodejs" {
  most_recent = true
  name_regex  = "^64bit Amazon Linux .* running Node.js .*"
}

resource "aws_s3_bucket" "beanstalk_source" {
  bucket        = "eb-bluegreen-source-${random_id.suffix.hex}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "beanstalk_source" {
  bucket = aws_s3_bucket.beanstalk_source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "archive_file" "nodejs_app" {
  type        = "zip"
  output_path = "${path.module}/beanstalk-nodejs-app.zip"

  source {
    filename = "package.json"

    content = jsonencode({
      scripts = {
        start = "node server.js"
      }

      dependencies = {
        express = "^4.18.2"
      }
    })
  }

  source {
    filename = "server.js"

    content = <<-EOT
      const express = require('express');
      const app = express();
      const port = process.env.PORT || 8080;

      app.get('/', (req, res) => {
        res.send('Blue/Green Elastic Beanstalk deployment managed by Terraform');
      });

      app.get('/health', (req, res) => {
        res.status(200).send('OK');
      });

      app.listen(port, () => {
        console.log(`Application listening on port ${port}`);
      });
    EOT
  }
}

resource "aws_s3_object" "application_bundle" {
  bucket = aws_s3_bucket.beanstalk_source.id
  key    = "beanstalk-nodejs-app-${random_id.suffix.hex}.zip"
  source = data.archive_file.nodejs_app.output_path
  etag   = data.archive_file.nodejs_app.output_md5
}

resource "aws_elastic_beanstalk_application" "bluegreen" {
  name        = "bluegreen-application-${random_id.suffix.hex}"
  description = "Elastic Beanstalk application for Blue/Green deployment using Route53 weighted routing."
}

resource "aws_elastic_beanstalk_application_version" "app_version" {
  name        = "v1-${random_id.suffix.hex}"
  application = aws_elastic_beanstalk_application.bluegreen.name
  bucket      = aws_s3_bucket.beanstalk_source.id
  key         = aws_s3_object.application_bundle.key
  description = "Initial deployable Node.js application version."
}

resource "aws_iam_role" "elastic_beanstalk_service_role" {
  name = "eb-service-role-${random_id.suffix.hex}"

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

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_service" {
  role       = aws_iam_role.elastic_beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkService"
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_enhanced_health" {
  role       = aws_iam_role.elastic_beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_iam_role" "elastic_beanstalk_ec2_role" {
  name = "eb-ec2-role-${random_id.suffix.hex}"

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
  name = "eb-instance-profile-${random_id.suffix.hex}"
  role = aws_iam_role.elastic_beanstalk_ec2_role.name
}

resource "aws_elastic_beanstalk_environment" "blue" {
  name                = "blue"
  application         = aws_elastic_beanstalk_application.bluegreen.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.nodejs.name
  version_label       = aws_elastic_beanstalk_application_version.app_version.name
  cname_prefix        = "blue-${random_id.suffix.hex}"

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
    value     = "t3.micro"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "ENVIRONMENT_COLOR"
    value     = "blue"
  }

  depends_on = [
    aws_iam_role_policy_attachment.elastic_beanstalk_service,
    aws_iam_role_policy_attachment.elastic_beanstalk_enhanced_health,
    aws_iam_role_policy_attachment.elastic_beanstalk_web_tier
  ]
}

resource "aws_elastic_beanstalk_environment" "green" {
  name                = "green"
  application         = aws_elastic_beanstalk_application.bluegreen.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.nodejs.name
  version_label       = aws_elastic_beanstalk_application_version.app_version.name
  cname_prefix        = "green-${random_id.suffix.hex}"

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
    value     = "t3.micro"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "ENVIRONMENT_COLOR"
    value     = "green"
  }

  depends_on = [
    aws_iam_role_policy_attachment.elastic_beanstalk_service,
    aws_iam_role_policy_attachment.elastic_beanstalk_enhanced_health,
    aws_iam_role_policy_attachment.elastic_beanstalk_web_tier
  ]
}

resource "aws_route53_zone" "bluegreen_zone" {
  name = var.domain_name
}

resource "aws_route53_record" "blue_weighted_record" {
  zone_id = aws_route53_zone.bluegreen_zone.zone_id
  name    = "${var.application_dns_name}.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "blue-environment"

  weighted_routing_policy {
    weight = var.blue_weight
  }

  records = [
    aws_elastic_beanstalk_environment.blue.cname
  ]
}

resource "aws_route53_record" "green_weighted_record" {
  zone_id = aws_route53_zone.bluegreen_zone.zone_id
  name    = "${var.application_dns_name}.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "green-environment"

  weighted_routing_policy {
    weight = var.green_weight
  }

  records = [
    aws_elastic_beanstalk_environment.green.cname
  ]
}

output "route53_name_servers" {
  description = "Name servers for the Route53 hosted zone. Configure these at your domain registrar."
  value       = aws_route53_zone.bluegreen_zone.name_servers
}

output "application_url" {
  description = "Weighted Blue/Green application URL."
  value       = "http://${var.application_dns_name}.${var.domain_name}"
}

output "blue_environment_cname" {
  description = "Elastic Beanstalk CNAME for the blue environment."
  value       = aws_elastic_beanstalk_environment.blue.cname
}

output "green_environment_cname" {
  description = "Elastic Beanstalk CNAME for the green environment."
  value       = aws_elastic_beanstalk_environment.green.cname
}

output "blue_weight" {
  description = "Current Route53 traffic weight for the blue environment."
  value       = var.blue_weight
}

output "green_weight" {
  description = "Current Route53 traffic weight for the green environment."
  value       = var.green_weight
}
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

    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
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
  description = "Domain name to manage with Route 53."
  type        = string
  default     = "example.com"
}

variable "record_name" {
  description = "Subdomain record that points to Elastic Beanstalk."
  type        = string
  default     = "app"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_route53_zone" "main" {
  name = var.domain_name
}

resource "aws_iam_role" "eb_ec2_role" {
  name = "eb_ec2_role"

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
  name = "eb_ec2_profile"
  role = aws_iam_role.eb_ec2_role.name
}

resource "aws_iam_role" "eb_service_role" {
  name = "eb_service_role"

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

resource "aws_iam_role_policy_attachment" "eb_service_enhanced_health" {
  role       = aws_iam_role.eb_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_iam_role_policy_attachment" "eb_service_managed_updates" {
  role       = aws_iam_role.eb_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy"
}

resource "aws_s3_bucket" "eb_source_bucket" {
  bucket = "myapp-eb-source-${random_id.bucket_suffix.hex}"
}

resource "aws_s3_bucket_ownership_controls" "eb_source_bucket" {
  bucket = aws_s3_bucket.eb_source_bucket.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "eb_source_bucket" {
  bucket = aws_s3_bucket.eb_source_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "archive_file" "app_source" {
  type        = "zip"
  output_path = "${path.module}/myapp.zip"

  source {
    filename = "package.json"
    content  = <<EOF
{
  "name": "myapp",
  "version": "1.0.0",
  "description": "Example Elastic Beanstalk Node.js application",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF
  }

  source {
    filename = "app.js"
    content  = <<EOF
const express = require('express');
const app = express();
const port = process.env.PORT || 8080;

app.get('/', (req, res) => {
  res.send('Hello from Elastic Beanstalk managed by Terraform!');
});

app.listen(port, () => {
  console.log(`Application listening on port ${port}`);
});
EOF
  }
}

resource "aws_s3_object" "examplebucket_object" {
  bucket = aws_s3_bucket.eb_source_bucket.id
  key    = "myapp/version.zip"
  source = data.archive_file.app_source.output_path
  etag   = data.archive_file.app_source.output_md5

  depends_on = [
    aws_s3_bucket_ownership_controls.eb_source_bucket,
    aws_s3_bucket_public_access_block.eb_source_bucket
  ]
}

resource "aws_elastic_beanstalk_application" "myapp" {
  name        = "myapp"
  description = "Elastic Beanstalk application managed by Terraform"
}

resource "aws_elastic_beanstalk_application_version" "version" {
  name        = "version"
  application = aws_elastic_beanstalk_application.myapp.name
  bucket      = aws_s3_bucket.eb_source_bucket.id
  key         = aws_s3_object.examplebucket_object.key
  description = "Application version uploaded from Terraform-managed S3 object"
}

resource "aws_elastic_beanstalk_environment" "eb_env" {
  name                = "eb-env"
  application         = aws_elastic_beanstalk_application.myapp.name
  solution_stack_name = "64bit Amazon Linux 2023 v6.4.1 running Node.js 20"
  version_label       = aws_elastic_beanstalk_application_version.version.name

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "SingleInstance"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.eb_service_role.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_ec2_profile.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = "t3.micro"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "NODE_ENV"
    value     = "production"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eb_ec2_web_tier,
    aws_iam_role_policy_attachment.eb_ec2_worker_tier,
    aws_iam_role_policy_attachment.eb_ec2_multicontainer_docker,
    aws_iam_role_policy_attachment.eb_service_enhanced_health,
    aws_iam_role_policy_attachment.eb_service_managed_updates
  ]
}

resource "aws_route53_record" "elastic_beanstalk_app" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "${var.record_name}.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300

  records = [
    aws_elastic_beanstalk_environment.eb_env.cname
  ]
}

output "route53_zone_id" {
  description = "Route 53 hosted zone ID."
  value       = aws_route53_zone.main.zone_id
}

output "route53_name_servers" {
  description = "Name servers for the Route 53 hosted zone."
  value       = aws_route53_zone.main.name_servers
}

output "elastic_beanstalk_environment_cname" {
  description = "Elastic Beanstalk environment CNAME."
  value       = aws_elastic_beanstalk_environment.eb_env.cname
}

output "application_url" {
  description = "DNS name that routes to the Elastic Beanstalk environment."
  value       = "http://${aws_route53_record.elastic_beanstalk_app.fqdn}"
}

output "source_bucket_name" {
  description = "Unique S3 bucket used for Elastic Beanstalk application source."
  value       = aws_s3_bucket.eb_source_bucket.bucket
}
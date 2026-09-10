terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_elastic_beanstalk_solution_stack" "php" {
  most_recent = true
  name_regex  = "^64bit Amazon Linux 2023.*PHP 8.*$"
}

data "archive_file" "app_zip" {
  type        = "zip"
  output_path = "${path.module}/myapp.zip"

  source {
    filename = "index.php"
    content  = <<EOF
<?php
echo "Hello from Elastic Beanstalk!";
?>
EOF
  }
}

resource "aws_s3_bucket" "app_bucket" {
  bucket = "sampleapril26426"
}

resource "aws_s3_bucket_public_access_block" "app_bucket_public_access" {
  bucket = aws_s3_bucket.app_bucket.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "examplebucket_object" {
  bucket       = aws_s3_bucket.app_bucket.id
  key          = "examplebucket_object"
  source       = data.archive_file.app_zip.output_path
  etag         = data.archive_file.app_zip.output_md5
  content_type = "application/zip"

  depends_on = [
    aws_s3_bucket_public_access_block.app_bucket_public_access
  ]
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
  name = "myapp-eb-service-role"

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

resource "aws_elastic_beanstalk_application" "myapp" {
  name        = "myapp"
  description = "Elastic Beanstalk application created by Terraform"
}

resource "aws_elastic_beanstalk_application_version" "version" {
  name        = "version"
  application = aws_elastic_beanstalk_application.myapp.name
  bucket      = aws_s3_bucket.app_bucket.id
  key         = aws_s3_object.examplebucket_object.key
  description = "Application version deployed from S3 object examplebucket_object"

  depends_on = [
    aws_s3_object.examplebucket_object
  ]
}

resource "aws_elastic_beanstalk_environment" "myapp_environment" {
  name                = "myapp-environment"
  application         = aws_elastic_beanstalk_application.myapp.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.php.name
  version_label       = aws_elastic_beanstalk_application_version.version.name

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_ec2_profile.name
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.eb_service_role.name
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "SingleInstance"
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = "t3.micro"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eb_ec2_web_tier,
    aws_iam_role_policy_attachment.eb_ec2_worker_tier,
    aws_iam_role_policy_attachment.eb_ec2_multicontainer_docker,
    aws_iam_role_policy_attachment.eb_service_enhanced_health,
    aws_iam_role_policy_attachment.eb_service_managed_updates,
    aws_elastic_beanstalk_application_version.version
  ]
}

output "elastic_beanstalk_application_name" {
  value = aws_elastic_beanstalk_application.myapp.name
}

output "elastic_beanstalk_application_version" {
  value = aws_elastic_beanstalk_application_version.version.name
}

output "elastic_beanstalk_environment_name" {
  value = aws_elastic_beanstalk_environment.myapp_environment.name
}

output "elastic_beanstalk_environment_endpoint" {
  value = aws_elastic_beanstalk_environment.myapp_environment.endpoint_url
}

output "s3_bucket_name" {
  value = aws_s3_bucket.app_bucket.bucket
}

output "s3_object_key" {
  value = aws_s3_object.examplebucket_object.key
}
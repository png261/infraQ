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

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# ------------------------------------------------------------------------------
# SQS Queue for Elastic Beanstalk Worker Environment
# ------------------------------------------------------------------------------

resource "aws_sqs_queue" "batch_job_queue" {
  name                       = "batch_job_queue"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 345600
}

# ------------------------------------------------------------------------------
# S3 Bucket for Elastic Beanstalk Application Version Source Bundle
# ------------------------------------------------------------------------------

resource "aws_s3_bucket" "sampleapril26426" {
  bucket = "sampleapril26426"
}

resource "aws_s3_bucket_ownership_controls" "sampleapril26426" {
  bucket = aws_s3_bucket.sampleapril26426.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "sampleapril26426" {
  bucket = aws_s3_bucket.sampleapril26426.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# Minimal Elastic Beanstalk Docker Worker Application Bundle
# ------------------------------------------------------------------------------

data "archive_file" "beanstalk_source_bundle" {
  type        = "zip"
  output_path = "${path.module}/beanstalk-worker-source.zip"

  source {
    filename = "Dockerrun.aws.json"

    content = jsonencode({
      AWSEBDockerrunVersion = "1"

      Image = {
        Name   = "public.ecr.aws/docker/library/python:3.11-slim"
        Update = "true"
      }

      Ports = [
        {
          ContainerPort = "80"
        }
      ]

      Command = "python -m http.server 80"
    })
  }
}

resource "aws_s3_object" "examplebucket_object" {
  bucket = aws_s3_bucket.sampleapril26426.id
  key    = "beanstalk-worker-source.zip"
  source = data.archive_file.beanstalk_source_bundle.output_path
  etag   = data.archive_file.beanstalk_source_bundle.output_md5

  depends_on = [
    aws_s3_bucket_ownership_controls.sampleapril26426,
    aws_s3_bucket_public_access_block.sampleapril26426
  ]
}

# ------------------------------------------------------------------------------
# IAM Role for Elastic Beanstalk EC2 Instances
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "eb_ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eb_ec2_role" {
  name               = "eb_ec2_role"
  assume_role_policy = data.aws_iam_policy_document.eb_ec2_assume_role.json
}

resource "aws_iam_instance_profile" "eb_ec2_profile" {
  name = "eb_ec2_profile"
  role = aws_iam_role.eb_ec2_role.name
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

data "aws_iam_policy_document" "eb_ec2_sqs_access" {
  statement {
    effect = "Allow"

    actions = [
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:ChangeMessageVisibility"
    ]

    resources = [
      aws_sqs_queue.batch_job_queue.arn
    ]
  }
}

resource "aws_iam_policy" "eb_ec2_sqs_access" {
  name        = "eb-ec2-batch-job-sqs-access"
  description = "Allows Elastic Beanstalk worker EC2 instances to consume messages from the batch job queue."
  policy      = data.aws_iam_policy_document.eb_ec2_sqs_access.json
}

resource "aws_iam_role_policy_attachment" "eb_ec2_sqs_access" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = aws_iam_policy.eb_ec2_sqs_access.arn
}

# ------------------------------------------------------------------------------
# IAM Service Role for Elastic Beanstalk
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "elastic_beanstalk_service_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type = "Service"

      identifiers = [
        "elasticbeanstalk.amazonaws.com"
      ]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "elastic_beanstalk_service_role" {
  name               = "elastic-beanstalk-service-role-batch"
  assume_role_policy = data.aws_iam_policy_document.elastic_beanstalk_service_assume_role.json
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_enhanced_health" {
  role       = aws_iam_role.elastic_beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_managed_updates" {
  role       = aws_iam_role.elastic_beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy"
}

# ------------------------------------------------------------------------------
# Elastic Beanstalk Application and Version
# ------------------------------------------------------------------------------

resource "aws_elastic_beanstalk_application" "batch_job_app" {
  name        = "batch_job_app"
  description = "Elastic Beanstalk application for running batch processing jobs."
}

resource "aws_elastic_beanstalk_application_version" "version" {
  name        = "version"
  application = aws_elastic_beanstalk_application.batch_job_app.name
  bucket      = aws_s3_bucket.sampleapril26426.id
  key         = aws_s3_object.examplebucket_object.key
  description = "Initial batch job worker application version."

  depends_on = [
    aws_s3_object.examplebucket_object
  ]
}

# ------------------------------------------------------------------------------
# Elastic Beanstalk Worker Environment
# ------------------------------------------------------------------------------

resource "aws_elastic_beanstalk_environment" "batch_job_worker_environment" {
  name                = "batch-job-worker-environment"
  application         = aws_elastic_beanstalk_application.batch_job_app.name
  version_label       = aws_elastic_beanstalk_application_version.version.name
  solution_stack_name = "64bit Amazon Linux 2 v3.8.3 running Docker"
  tier                = "Worker"

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_ec2_profile.name
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.elastic_beanstalk_service_role.name
  }

  setting {
    namespace = "aws:elasticbeanstalk:sqsd"
    name      = "WorkerQueueURL"
    value     = aws_sqs_queue.batch_job_queue.id
  }

  setting {
    namespace = "aws:elasticbeanstalk:sqsd"
    name      = "HttpPath"
    value     = "/"
  }

  setting {
    namespace = "aws:elasticbeanstalk:sqsd"
    name      = "MimeType"
    value     = "application/json"
  }

  setting {
    namespace = "aws:elasticbeanstalk:sqsd"
    name      = "HttpConnections"
    value     = "10"
  }

  setting {
    namespace = "aws:elasticbeanstalk:sqsd"
    name      = "ConnectTimeout"
    value     = "5"
  }

  setting {
    namespace = "aws:elasticbeanstalk:sqsd"
    name      = "InactivityTimeout"
    value     = "299"
  }

  setting {
    namespace = "aws:elasticbeanstalk:sqsd"
    name      = "VisibilityTimeout"
    value     = "300"
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
    namespace = "aws:ec2:instances"
    name      = "InstanceTypes"
    value     = "t3.micro"
  }

  depends_on = [
    aws_iam_role_policy_attachment.eb_ec2_web_tier,
    aws_iam_role_policy_attachment.eb_ec2_worker_tier,
    aws_iam_role_policy_attachment.eb_ec2_multicontainer_docker,
    aws_iam_role_policy_attachment.eb_ec2_sqs_access,
    aws_iam_role_policy_attachment.elastic_beanstalk_enhanced_health,
    aws_iam_role_policy_attachment.elastic_beanstalk_managed_updates
  ]
}

# ------------------------------------------------------------------------------
# Outputs
# ------------------------------------------------------------------------------

output "elastic_beanstalk_application_name" {
  value = aws_elastic_beanstalk_application.batch_job_app.name
}

output "elastic_beanstalk_environment_name" {
  value = aws_elastic_beanstalk_environment.batch_job_worker_environment.name
}

output "sqs_queue_url" {
  value = aws_sqs_queue.batch_job_queue.id
}

output "sqs_queue_arn" {
  value = aws_sqs_queue.batch_job_queue.arn
}

output "s3_bucket_name" {
  value = aws_s3_bucket.sampleapril26426.bucket
}

output "application_version_name" {
  value = aws_elastic_beanstalk_application_version.version.name
}
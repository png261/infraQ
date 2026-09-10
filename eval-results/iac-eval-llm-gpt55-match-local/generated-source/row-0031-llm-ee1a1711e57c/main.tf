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

variable "application_version_label" {
  description = "Label for the initial Elastic Beanstalk application version."
  type        = string
  default     = "v1"
}

variable "max_application_versions" {
  description = "Maximum number of application versions to retain."
  type        = number
  default     = 5
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_iam_role" "elastic_beanstalk_service_role" {
  name = "elastic-beanstalk-app-version-lifecycle-role"

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

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_service_role_policy" {
  role       = aws_iam_role.elastic_beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkServiceRolePolicy"
}

resource "aws_s3_bucket" "application_versions" {
  bucket = "eb-app-versions-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"
}

resource "aws_s3_bucket_public_access_block" "application_versions" {
  bucket = aws_s3_bucket.application_versions.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "application_versions" {
  bucket = aws_s3_bucket.application_versions.id

  versioning_configuration {
    status = "Enabled"
  }
}

data "archive_file" "application_source" {
  type        = "zip"
  output_path = "${path.module}/elastic-beanstalk-app.zip"

  source {
    filename = "index.html"
    content  = <<-EOF
      <!DOCTYPE html>
      <html>
        <head>
          <title>Elastic Beanstalk App</title>
        </head>
        <body>
          <h1>Hello from Elastic Beanstalk</h1>
        </body>
      </html>
    EOF
  }
}

resource "aws_s3_object" "application_source" {
  bucket = aws_s3_bucket.application_versions.id
  key    = "application-versions/${var.application_version_label}/elastic-beanstalk-app.zip"
  source = data.archive_file.application_source.output_path
  etag   = data.archive_file.application_source.output_md5

  depends_on = [
    aws_s3_bucket_public_access_block.application_versions,
    aws_s3_bucket_versioning.application_versions
  ]
}

resource "aws_elastic_beanstalk_application" "application" {
  name        = var.application_name
  description = "Elastic Beanstalk application with application version lifecycle management."

  appversion_lifecycle {
    service_role          = aws_iam_role.elastic_beanstalk_service_role.arn
    max_count             = var.max_application_versions
    delete_source_from_s3 = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.elastic_beanstalk_service_role_policy
  ]
}

resource "aws_elastic_beanstalk_application_version" "initial_version" {
  name        = var.application_version_label
  application = aws_elastic_beanstalk_application.application.name
  description = "Initial application version for ${var.application_name}"

  bucket = aws_s3_bucket.application_versions.id
  key    = aws_s3_object.application_source.key
}

output "elastic_beanstalk_application_name" {
  description = "Name of the Elastic Beanstalk application."
  value       = aws_elastic_beanstalk_application.application.name
}

output "elastic_beanstalk_application_version" {
  description = "Initial Elastic Beanstalk application version label."
  value       = aws_elastic_beanstalk_application_version.initial_version.name
}

output "application_versions_bucket" {
  description = "S3 bucket used to store Elastic Beanstalk application source bundles."
  value       = aws_s3_bucket.application_versions.bucket
}

output "application_version_lifecycle_max_count" {
  description = "Maximum number of Elastic Beanstalk application versions retained."
  value       = var.max_application_versions
}
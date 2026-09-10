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
  description = "AWS region to deploy the Elastic Beanstalk application into."
  type        = string
  default     = "us-east-1"
}

variable "application_name" {
  description = "Name of the Elastic Beanstalk application."
  type        = string
  default     = "go-elastic-beanstalk-app"
}

variable "environment_name" {
  description = "Name of the Elastic Beanstalk environment."
  type        = string
  default     = "go-elastic-beanstalk-env"
}

variable "application_version_label" {
  description = "Elastic Beanstalk application version label."
  type        = string
  default     = "v1"
}

data "aws_caller_identity" "current" {}

data "aws_elastic_beanstalk_solution_stack" "go" {
  most_recent = true
  name_regex  = "^64bit Amazon Linux 2023 .* running Go .*$"
}

data "archive_file" "go_application_zip" {
  type        = "zip"
  output_path = "${path.module}/go-elastic-beanstalk-app.zip"

  source {
    filename = "go.mod"
    content  = <<EOF
module example.com/go-elastic-beanstalk-app

go 1.21
EOF
  }

  source {
    filename = "main.go"
    content  = <<EOF
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "5000"
	}

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Hello from Go running on AWS Elastic Beanstalk!\\n")
	})

	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprintf(w, "ok\\n")
	})

	log.Printf("Starting server on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
EOF
  }

  source {
    filename = "Makefile"
    content  = <<EOF
build:
	mkdir -p bin
	go build -o bin/application .
EOF
  }

  source {
    filename = "Procfile"
    content  = <<EOF
web: bin/application
EOF
  }
}

resource "aws_s3_bucket" "beanstalk_source_bundle" {
  bucket = "${var.application_name}-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "beanstalk_source_bundle" {
  bucket = aws_s3_bucket.beanstalk_source_bundle.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "beanstalk_source_bundle" {
  bucket = aws_s3_bucket.beanstalk_source_bundle.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "go_application_zip" {
  bucket = aws_s3_bucket.beanstalk_source_bundle.id
  key    = "versions/${var.application_version_label}/go-elastic-beanstalk-app.zip"
  source = data.archive_file.go_application_zip.output_path
  etag   = data.archive_file.go_application_zip.output_md5
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
        Condition = {
          StringEquals = {
            "sts:ExternalId" = "elasticbeanstalk"
          }
        }
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

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_ssm" {
  role       = aws_iam_role.elastic_beanstalk_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "elastic_beanstalk_instance_profile" {
  name = "${var.application_name}-eb-instance-profile"
  role = aws_iam_role.elastic_beanstalk_ec2_role.name
}

resource "aws_elastic_beanstalk_application" "go_app" {
  name        = var.application_name
  description = "Elastic Beanstalk application running a Go web server."
}

resource "aws_elastic_beanstalk_application_version" "go_app_version" {
  name        = var.application_version_label
  application = aws_elastic_beanstalk_application.go_app.name
  bucket      = aws_s3_bucket.beanstalk_source_bundle.id
  key         = aws_s3_object.go_application_zip.key
  description = "Go application version ${var.application_version_label}"

  depends_on = [
    aws_s3_object.go_application_zip
  ]
}

resource "aws_elastic_beanstalk_environment" "go_environment" {
  name                = var.environment_name
  application         = aws_elastic_beanstalk_application.go_app.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.go.name
  version_label       = aws_elastic_beanstalk_application_version.go_app_version.name

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
    name      = "PORT"
    value     = "5000"
  }

  setting {
    namespace = "aws:elasticbeanstalk:healthreporting:system"
    name      = "SystemType"
    value     = "enhanced"
  }

  depends_on = [
    aws_iam_role_policy_attachment.elastic_beanstalk_enhanced_health,
    aws_iam_role_policy_attachment.elastic_beanstalk_managed_updates,
    aws_iam_role_policy_attachment.elastic_beanstalk_web_tier,
    aws_iam_role_policy_attachment.elastic_beanstalk_worker_tier,
    aws_iam_role_policy_attachment.elastic_beanstalk_ssm
  ]
}

output "elastic_beanstalk_application_name" {
  description = "Name of the Elastic Beanstalk application."
  value       = aws_elastic_beanstalk_application.go_app.name
}

output "elastic_beanstalk_environment_name" {
  description = "Name of the Elastic Beanstalk environment."
  value       = aws_elastic_beanstalk_environment.go_environment.name
}

output "elastic_beanstalk_environment_url" {
  description = "URL of the Elastic Beanstalk environment."
  value       = aws_elastic_beanstalk_environment.go_environment.endpoint_url
}

output "go_solution_stack" {
  description = "Elastic Beanstalk Go solution stack selected."
  value       = data.aws_elastic_beanstalk_solution_stack.go.name
}
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
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name of the AWS CodeBuild project."
  type        = string
  default     = "students-codebuild-project"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "codebuild_output" {
  bucket = "students-codebuild-output-${random_id.bucket_suffix.hex}"

  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "codebuild_output" {
  bucket = aws_s3_bucket.codebuild_output.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_vpc" "codebuild_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "codebuild-vpc"
  }
}

resource "aws_subnet" "codebuild_subnet" {
  vpc_id                  = aws_vpc.codebuild_vpc.id
  cidr_block              = "10.0.0.0/24"
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = false

  tags = {
    Name = "codebuild-subnet"
  }
}

resource "aws_security_group" "codebuild_sg" {
  name        = "codebuild-no-internet-sg"
  description = "Security group with no ingress or egress rules to block internet access"
  vpc_id      = aws_vpc.codebuild_vpc.id

  ingress = []
  egress  = []

  tags = {
    Name = "codebuild-no-internet-sg"
  }
}

resource "aws_iam_role" "codebuild_role" {
  name = "students-codebuild-service-role-${random_id.bucket_suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild_policy" {
  name = "students-codebuild-service-policy"
  role = aws_iam_role.codebuild_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketLocation",
          "s3:GetBucketAcl",
          "s3:ListBucket"
        ]
        Resource = aws_s3_bucket.codebuild_output.arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:PutObjectAcl"
        ]
        Resource = "${aws_s3_bucket.codebuild_output.arn}/*"
      },
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeDhcpOptions",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeVpcs"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterfacePermission"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:Subnet" = aws_subnet.codebuild_subnet.arn
          }
        }
      }
    ]
  })
}

resource "aws_codebuild_project" "students_codebuild" {
  name          = var.project_name
  description   = "CodeBuild project for students' code build output"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = 60

  artifacts {
    type     = "S3"
    location = aws_s3_bucket.codebuild_output.bucket
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "alpine"
    type         = "LINUX_CONTAINER"
  }

  source {
    type            = "GITHUB"
    git_clone_depth = 1
    location        = "github.com/source-location"
  }

  vpc_config {
    vpc_id             = aws_vpc.codebuild_vpc.id
    subnets            = [aws_subnet.codebuild_subnet.id]
    security_group_ids = [aws_security_group.codebuild_sg.id]
  }

  tags = {
    Name = var.project_name
  }

  depends_on = [
    aws_iam_role_policy.codebuild_policy,
    aws_s3_bucket_public_access_block.codebuild_output
  ]
}

output "s3_bucket_name" {
  description = "Name of the S3 bucket storing CodeBuild output."
  value       = aws_s3_bucket.codebuild_output.bucket
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.codebuild_vpc.id
}

output "subnet_id" {
  description = "ID of the created subnet."
  value       = aws_subnet.codebuild_subnet.id
}

output "security_group_id" {
  description = "ID of the no-ingress no-egress security group."
  value       = aws_security_group.codebuild_sg.id
}

output "codebuild_project_name" {
  description = "Name of the CodeBuild project."
  value       = aws_codebuild_project.students_codebuild.name
}
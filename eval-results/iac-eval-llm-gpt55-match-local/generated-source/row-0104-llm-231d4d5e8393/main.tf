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
  description = "AWS region where the S3 bucket will be created."
  type        = string
  default     = "us-east-1"
}

variable "denied_ip_cidr" {
  description = "The specific IP address or CIDR block to deny access from."
  type        = string
  default     = "203.0.113.10/32"
}

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "my_bucket" {
  bucket = "my-bucket-${random_id.bucket_suffix.hex}"

  tags = {
    Name = "my_bucket"
  }
}

resource "aws_s3_bucket_policy" "deny_specific_ip" {
  bucket = aws_s3_bucket.my_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "DenyAccessFromSpecificIP"

    Statement = [
      {
        Sid       = "DenyAllS3ActionsFromSpecificIP"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"

        Resource = [
          aws_s3_bucket.my_bucket.arn,
          "${aws_s3_bucket.my_bucket.arn}/*"
        ]

        Condition = {
          IpAddress = {
            "aws:SourceIp" = var.denied_ip_cidr
          }
        }
      }
    ]
  })
}
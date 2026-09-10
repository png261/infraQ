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

    local = {
      source  = "hashicorp/local"
      version = ">= 2.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the S3 buckets will be created."
  type        = string
  default     = "us-east-1"
}

variable "bucket_suffix" {
  description = "Suffix used in the dynamic S3 bucket names."
  type        = string
  default     = "test"
}

variable "local_order_data_file_path" {
  description = "Local file path for the order_data2.csv file to upload."
  type        = string
  default     = "order_data2.csv"
}

resource "random_id" "bucket_id" {
  byte_length = 4
}

locals {
  cloudgoat_data_bucket_name = "cloudgoat-data-${var.bucket_suffix}-${random_id.bucket_id.hex}"
  web_data_bucket_name       = "cloudgoat-web-data-${var.bucket_suffix}-${random_id.bucket_id.hex}"
}

resource "local_file" "order_data_csv" {
  filename = var.local_order_data_file_path

  content = <<-EOT
order_id,customer_id,item,quantity,price
1001,501,widget,2,19.99
1002,502,gadget,1,29.99
1003,503,doohickey,5,4.99
EOT
}

resource "aws_s3_bucket" "cloudgoat_data" {
  bucket = local.cloudgoat_data_bucket_name
}

resource "aws_s3_bucket_ownership_controls" "cloudgoat_data" {
  bucket = aws_s3_bucket.cloudgoat_data.id

  rule {
    object_ownership = "ObjectWriter"
  }
}

resource "aws_s3_bucket_acl" "cloudgoat_data" {
  bucket = aws_s3_bucket.cloudgoat_data.id
  acl    = "private"

  depends_on = [
    aws_s3_bucket_ownership_controls.cloudgoat_data
  ]
}

resource "aws_s3_bucket" "web_data" {
  bucket = local.web_data_bucket_name
}

resource "aws_s3_bucket_ownership_controls" "web_data" {
  bucket = aws_s3_bucket.web_data.id

  rule {
    object_ownership = "ObjectWriter"
  }
}

resource "aws_s3_bucket_acl" "web_data" {
  bucket = aws_s3_bucket.web_data.id
  acl    = "private"

  depends_on = [
    aws_s3_bucket_ownership_controls.web_data
  ]
}

resource "aws_s3_bucket_public_access_block" "web_data" {
  bucket = aws_s3_bucket.web_data.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = false
  restrict_public_buckets = true
}

resource "aws_s3_object" "order_data2" {
  bucket = aws_s3_bucket.web_data.id
  key    = "order_data2.csv"
  source = local_file.order_data_csv.filename
  etag   = filemd5(local_file.order_data_csv.filename)

  content_type = "text/csv"

  depends_on = [
    local_file.order_data_csv
  ]
}

resource "aws_s3_bucket_policy" "web_data_put_object_policy" {
  bucket = aws_s3_bucket.web_data.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowPutObjectForAllPrincipals"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.web_data.arn}/*"
      }
    ]
  })

  depends_on = [
    aws_s3_bucket_public_access_block.web_data
  ]
}

output "cloudgoat_data_bucket_name" {
  description = "Name of the CloudGoat data storage S3 bucket."
  value       = aws_s3_bucket.cloudgoat_data.bucket
}

output "web_data_bucket_name" {
  description = "Name of the web data storage S3 bucket."
  value       = aws_s3_bucket.web_data.bucket
}

output "uploaded_object_key" {
  description = "Uploaded S3 object key."
  value       = aws_s3_object.order_data2.key
}
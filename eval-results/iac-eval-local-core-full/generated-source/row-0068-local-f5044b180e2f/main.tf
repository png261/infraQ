terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_kinesis_video_stream" "basic" {
  name                    = "basic-kinesis-video-stream"
  data_retention_in_hours = 24
}

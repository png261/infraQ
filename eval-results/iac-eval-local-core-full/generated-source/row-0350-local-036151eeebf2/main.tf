terraform {
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

resource "aws_db_option_group" "option_group_pike" {
  name                 = "option-group-pike"
  engine_name          = "sqlserver-ee"
  major_engine_version = "11.00"
}

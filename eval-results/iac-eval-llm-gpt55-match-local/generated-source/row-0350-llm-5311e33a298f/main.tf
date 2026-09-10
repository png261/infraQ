terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_db_option_group" "option_group_pike" {
  name                     = "option-group-pike"
  option_group_description = "Option group for SQL Server Enterprise Edition major version 11"
  engine_name              = "sqlserver-ee"
  major_engine_version     = "11.00"

  tags = {
    Name = "option-group-pike"
  }
}
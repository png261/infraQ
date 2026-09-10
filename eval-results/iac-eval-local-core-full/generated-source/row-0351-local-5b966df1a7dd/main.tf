terraform {
  required_version = ">= 1.0"

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

resource "aws_db_option_group" "pike" {
  name                 = "option-group-pike"
  option_group_description = "Option group for SQL Server Enterprise Edition with audit and TDE options"
  engine_name          = "sqlserver-ee"
  major_engine_version = "11.00"

  option {
    option_name = "SQLSERVER_AUDIT"
  }

  option {
    option_name = "TDE"
  }
}

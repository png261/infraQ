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

resource "aws_dax_parameter_group" "this" {
  name        = var.parameter_group_name
  description = var.description

  dynamic "parameters" {
    for_each = { for parameter in var.parameters : parameter.key => parameter.value }

    content {
      name  = parameters.key
      value = parameters.value
    }
  }
}

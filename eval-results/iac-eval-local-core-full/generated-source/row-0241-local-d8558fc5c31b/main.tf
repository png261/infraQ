terraform {
  required_version = ">= 1.5.0"

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

resource "aws_neptune_cluster_parameter_group" "custom" {
  name        = "basic-neptune-custom-params"
  family      = "neptune1.2"
  description = "Custom parameter group for the basic Neptune cluster"
}

resource "aws_neptune_cluster" "basic" {
  cluster_identifier                  = "basic-neptune-cluster"
  engine                              = "neptune"
  neptune_cluster_parameter_group_name = aws_neptune_cluster_parameter_group.custom.name
  skip_final_snapshot                 = true
}

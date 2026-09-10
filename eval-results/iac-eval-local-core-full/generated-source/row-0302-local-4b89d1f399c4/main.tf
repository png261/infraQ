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

resource "aws_s3_bucket" "cat_pictures" {
  bucket_prefix = "cat-pictures-"
}

resource "aws_api_gateway_rest_api" "cat_api" {
  name = "cat-pictures-api"
}

resource "aws_api_gateway_resource" "cats" {
  rest_api_id = aws_api_gateway_rest_api.cat_api.id
  parent_id   = aws_api_gateway_rest_api.cat_api.root_resource_id
  path_part   = "cats"
}

resource "aws_api_gateway_method" "get_cat" {
  rest_api_id   = aws_api_gateway_rest_api.cat_api.id
  resource_id   = aws_api_gateway_resource.cats.id
  http_method   = "GET"
  authorization = "NONE"
}

resource "aws_api_gateway_method" "put_cat" {
  rest_api_id   = aws_api_gateway_rest_api.cat_api.id
  resource_id   = aws_api_gateway_resource.cats.id
  http_method   = "PUT"
  authorization = "NONE"
}

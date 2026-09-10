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

data "aws_iam_policy_document" "dax_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["dax.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "dax" {
  name               = "example-dax-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.dax_assume_role.json
}

resource "aws_iam_role_policy_attachment" "dax_dynamodb_access" {
  role       = aws_iam_role.dax.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBReadOnlyAccess"
}

resource "aws_dax_cluster" "example" {
  cluster_name       = "example-dax-cluster"
  iam_role_arn       = aws_iam_role.dax.arn
  node_type          = "dax.r4.large"
  replication_factor = 1

  depends_on = [aws_iam_role_policy_attachment.dax_dynamodb_access]
}

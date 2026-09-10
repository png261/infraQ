data "aws_iam_policy_document" "sagemaker_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "sagemaker_execution" {
  name               = "iac-eval-sagemaker-execution-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role.json
}

resource "aws_vpc" "sagemaker" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "iac-eval-sagemaker-vpc"
  }
}

resource "aws_subnet" "sagemaker" {
  vpc_id                  = aws_vpc.sagemaker.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "iac-eval-sagemaker-subnet"
  }
}

resource "aws_sagemaker_domain" "this" {
  domain_name = "iac-eval-sagemaker-domain"
  auth_mode   = "IAM"
  vpc_id      = aws_vpc.sagemaker.id
  subnet_ids  = [aws_subnet.sagemaker.id]

  default_user_settings {
    execution_role = aws_iam_role.sagemaker_execution.arn
  }
}

resource "aws_sagemaker_space" "this" {
  domain_id  = aws_sagemaker_domain.this.id
  space_name = "iac-eval-sagemaker-space"
}

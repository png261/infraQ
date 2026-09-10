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

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "iac-eval-sagemaker-vpc"
  }
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "iac-eval-sagemaker-subnet-a"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"

  tags = {
    Name = "iac-eval-sagemaker-subnet-b"
  }
}

resource "aws_sagemaker_domain" "main" {
  domain_name = "iac-eval-sagemaker-domain"
  auth_mode   = "IAM"
  vpc_id      = aws_vpc.main.id
  subnet_ids = [
    aws_subnet.private_a.id,
    aws_subnet.private_b.id,
  ]

  default_user_settings {
    execution_role = aws_iam_role.sagemaker_execution.arn
  }
}

resource "aws_sagemaker_user_profile" "main" {
  domain_id         = aws_sagemaker_domain.main.id
  user_profile_name = "iac-eval-user-profile"

  user_settings {
    execution_role = aws_iam_role.sagemaker_execution.arn
  }
}

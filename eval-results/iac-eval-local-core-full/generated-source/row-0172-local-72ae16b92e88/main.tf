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

  tags = {
    Name        = "iac-eval-sagemaker-execution-role"
    Environment = "dev"
  }
}

resource "aws_iam_role_policy_attachment" "sagemaker_execution" {
  role       = aws_iam_role.sagemaker_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_vpc" "sagemaker" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "iac-eval-sagemaker-vpc"
    Environment = "dev"
  }
}

resource "aws_subnet" "sagemaker" {
  vpc_id                  = aws_vpc.sagemaker.id
  cidr_block              = "10.42.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = false

  tags = {
    Name        = "iac-eval-sagemaker-subnet"
    Environment = "dev"
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

  tags = {
    Name        = "iac-eval-sagemaker-domain"
    Environment = "dev"
  }

  depends_on = [aws_iam_role_policy_attachment.sagemaker_execution]
}

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
  name               = "sagemaker-jupyterserver-execution-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role.json

  tags = {
    Name = "sagemaker-jupyterserver-execution-role"
  }
}

resource "aws_vpc" "sagemaker" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "sagemaker-jupyterserver-vpc"
  }
}

resource "aws_subnet" "sagemaker" {
  vpc_id            = aws_vpc.sagemaker.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "sagemaker-jupyterserver-subnet"
  }
}

resource "aws_sagemaker_domain" "jupyter" {
  domain_name = "sagemaker-jupyterserver-domain"
  auth_mode   = "IAM"
  vpc_id      = aws_vpc.sagemaker.id
  subnet_ids  = [aws_subnet.sagemaker.id]

  default_user_settings {
    execution_role = aws_iam_role.sagemaker_execution.arn
  }

  tags = {
    Name = "sagemaker-jupyterserver-domain"
  }
}

resource "aws_sagemaker_user_profile" "jupyter" {
  domain_id         = aws_sagemaker_domain.jupyter.id
  user_profile_name = "jupyter-user"

  user_settings {
    execution_role = aws_iam_role.sagemaker_execution.arn
  }

  tags = {
    Name = "jupyter-user"
  }
}

resource "aws_sagemaker_app" "jupyter_server" {
  domain_id         = aws_sagemaker_domain.jupyter.id
  user_profile_name = aws_sagemaker_user_profile.jupyter.user_profile_name
  app_name          = "default"
  app_type          = "JupyterServer"

  tags = {
    Name = "sagemaker-jupyterserver-app"
  }
}

terraform {
  required_version = ">= 1.3.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region where the SageMaker notebook instance will be created."
  type        = string
  default     = "us-east-1"
}

variable "notebook_instance_name" {
  description = "Name of the SageMaker notebook instance."
  type        = string
  default     = "terraform-provider-aws-notebook"
}

variable "notebook_instance_type" {
  description = "Instance type for the SageMaker notebook instance."
  type        = string
  default     = "ml.t3.medium"
}

variable "github_repository_url" {
  description = "GitHub repository URL to clone into the SageMaker notebook instance."
  type        = string
  default     = "https://github.com/hashicorp/terraform-provider-aws.git"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_iam_role" "sagemaker_execution_role" {
  name = "sagemaker-notebook-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "sagemaker.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sagemaker_full_access" {
  role       = aws_iam_role.sagemaker_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSageMakerFullAccess"
}

resource "aws_iam_role_policy" "sagemaker_notebook_additional_policy" {
  name = "sagemaker-notebook-additional-policy"
  role = aws_iam_role.sagemaker_execution_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:DescribeLogStreams",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:ListAllMyBuckets",
          "s3:GetBucketLocation"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_sagemaker_notebook_instance_lifecycle_configuration" "clone_github_repo" {
  name = "clone-terraform-provider-aws-repo"

  on_start = base64encode(<<-EOT
    #!/bin/bash
    set -e

    NOTEBOOK_USER="ec2-user"
    REPO_URL="${var.github_repository_url}"
    REPO_DIR="/home/ec2-user/SageMaker/terraform-provider-aws"

    sudo -u $NOTEBOOK_USER -i <<'EOF'
    if [ ! -d "/home/ec2-user/SageMaker/terraform-provider-aws/.git" ]; then
      cd /home/ec2-user/SageMaker
      git clone https://github.com/hashicorp/terraform-provider-aws.git
    else
      cd /home/ec2-user/SageMaker/terraform-provider-aws
      git pull
    fi
    EOF

    chown -R ec2-user:ec2-user /home/ec2-user/SageMaker/terraform-provider-aws
  EOT)
}

resource "aws_sagemaker_notebook_instance" "terraform_provider_aws_notebook" {
  name                    = var.notebook_instance_name
  role_arn                = aws_iam_role.sagemaker_execution_role.arn
  instance_type           = var.notebook_instance_type
  lifecycle_config_name   = aws_sagemaker_notebook_instance_lifecycle_configuration.clone_github_repo.name
  direct_internet_access  = "Enabled"
  root_access             = "Enabled"
  volume_size             = 20

  tags = {
    Name        = var.notebook_instance_name
    Repository  = var.github_repository_url
    Environment = "development"
    ManagedBy   = "terraform"
  }

  depends_on = [
    aws_iam_role_policy_attachment.sagemaker_full_access,
    aws_iam_role_policy.sagemaker_notebook_additional_policy
  ]
}

output "sagemaker_notebook_instance_name" {
  description = "Name of the SageMaker notebook instance."
  value       = aws_sagemaker_notebook_instance.terraform_provider_aws_notebook.name
}

output "sagemaker_notebook_instance_arn" {
  description = "ARN of the SageMaker notebook instance."
  value       = aws_sagemaker_notebook_instance.terraform_provider_aws_notebook.arn
}

output "github_repository_cloned" {
  description = "GitHub repository configured to be cloned into the notebook instance."
  value       = var.github_repository_url
}
terraform {
  required_version = ">= 1.0.0"

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

resource "aws_iam_role" "eks_fargate_profile_role" {
  name = "eks-fargate-profile-example"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks-fargate-pods.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_fargate_pod_execution_policy_attachment" {
  role       = aws_iam_role.eks_fargate_profile_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSFargatePodExecutionRolePolicy"
}

output "eks_fargate_profile_role_name" {
  value = aws_iam_role.eks_fargate_profile_role.name
}

output "eks_fargate_profile_role_arn" {
  value = aws_iam_role.eks_fargate_profile_role.arn
}
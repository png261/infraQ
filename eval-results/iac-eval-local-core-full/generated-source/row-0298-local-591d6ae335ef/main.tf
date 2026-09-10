data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "codebuild_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "codebuild_permissions" {
  statement {
    sid    = "WriteBuildLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "WriteArtifacts"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:PutObject",
      "s3:PutObjectAcl"
    ]
    resources = [
      aws_s3_bucket.autograder_results.arn,
      "${aws_s3_bucket.autograder_results.arn}/*"
    ]
  }

  statement {
    sid    = "ManageVpcNetworkInterfaces"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:DeleteNetworkInterface",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs"
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCodeBuildNetworkInterfacePermission"
    effect = "Allow"
    actions = ["ec2:CreateNetworkInterfacePermission"]
    resources = ["arn:aws:ec2:us-east-1:${data.aws_caller_identity.current.account_id}:network-interface/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:AuthorizedService"
      values   = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket" "autograder_results" {
  bucket        = "${var.project_name}-${data.aws_caller_identity.current.account_id}-results"
  force_destroy = true
}

resource "aws_vpc" "autograder" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-isolated-vpc"
  }
}

resource "aws_subnet" "autograder" {
  vpc_id                  = aws_vpc.autograder.id
  cidr_block              = var.subnet_cidr_block
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-isolated-subnet"
  }
}

resource "aws_security_group" "codebuild" {
  name        = "${var.project_name}-codebuild-no-egress"
  description = "No ingress or egress; prevents student code from reaching the internet."
  vpc_id      = aws_vpc.autograder.id

  tags = {
    Name = "${var.project_name}-codebuild-no-egress"
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${var.project_name}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
}

resource "aws_iam_policy" "codebuild" {
  name   = "${var.project_name}-codebuild-policy"
  policy = data.aws_iam_policy_document.codebuild_permissions.json
}

resource "aws_iam_role_policy_attachment" "codebuild" {
  role       = aws_iam_role.codebuild.name
  policy_arn = aws_iam_policy.codebuild.arn
}

resource "aws_codebuild_project" "autograder" {
  name         = var.project_name
  description  = "Runs CS autograder workloads from GitHub in an isolated VPC subnet."
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type      = "S3"
    location  = aws_s3_bucket.autograder_results.bucket
    name      = "autograder-results"
    packaging = "ZIP"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "aws/codebuild/standard:7.0"
    type         = "LINUX_CONTAINER"
  }

  source {
    type      = "GITHUB"
    location  = var.github_repository_url
    buildspec = <<-EOT
      version: 0.2
      phases:
        build:
          commands:
            - echo "Run autograder here"
      artifacts:
        files:
          - '**/*'
    EOT
  }

  vpc_config {
    vpc_id             = aws_vpc.autograder.id
    subnets            = [aws_subnet.autograder.id]
    security_group_ids = [aws_security_group.codebuild.id]
  }
}

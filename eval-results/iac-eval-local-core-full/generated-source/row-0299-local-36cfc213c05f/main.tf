data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

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
    sid    = "WriteAutograderResults"
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetObjectVersion"
    ]

    resources = [
      aws_s3_bucket.results.arn,
      "${aws_s3_bucket.results.arn}/*"
    ]
  }

  statement {
    sid    = "WriteBuildLogs"
    effect = "Allow"

    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = [
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.project_name}",
      "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/codebuild/${var.project_name}:*"
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
    sid    = "CreateCodeBuildNetworkInterfacePermission"
    effect = "Allow"

    actions = ["ec2:CreateNetworkInterfacePermission"]

    resources = [
      "arn:aws:ec2:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:network-interface/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "ec2:AuthorizedService"
      values   = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_s3_bucket" "results" {
  bucket_prefix = "${var.project_name}-results-"
}

resource "aws_vpc" "autograder" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "autograder" {
  vpc_id                  = aws_vpc.autograder.id
  cidr_block              = "10.42.1.0/24"
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-private-subnet"
  }
}

resource "aws_security_group" "codebuild" {
  name        = "${var.project_name}-codebuild"
  description = "No internet egress for untrusted student code; only S3 endpoint traffic is allowed."
  vpc_id      = aws_vpc.autograder.id

  egress {
    description     = "Allow HTTPS only to S3 through the gateway endpoint prefix list"
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    prefix_list_ids = [aws_vpc_endpoint.s3.prefix_list_id]
  }

  tags = {
    Name = "${var.project_name}-codebuild-sg"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.autograder.id
  service_name      = "com.amazonaws.${data.aws_region.current.name}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_vpc.autograder.default_route_table_id]
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
  description  = "VPC-isolated CS autograder for GitHub-hosted student code"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type      = "S3"
    location  = aws_s3_bucket.results.bucket
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
    location  = var.github_source_location
    buildspec = <<-EOT
      version: 0.2
      phases:
        build:
          commands:
            - echo "Run course autograder commands here"
            - mkdir -p results
            - echo "autograder result placeholder" > results/result.txt
      artifacts:
        files:
          - results/**/*
    EOT
  }

  vpc_config {
    vpc_id             = aws_vpc.autograder.id
    subnets            = [aws_subnet.autograder.id]
    security_group_ids = [aws_security_group.codebuild.id]
  }
}

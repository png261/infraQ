data "aws_iam_policy_document" "codebuild_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "codebuild_permissions" {
  statement {
    sid = "WriteBuildLogs"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }

  statement {
    sid = "WriteArtifacts"
    actions = [
      "s3:GetBucketLocation",
      "s3:PutObject",
      "s3:GetObject"
    ]
    resources = [
      aws_s3_bucket.results.arn,
      "${aws_s3_bucket.results.arn}/*"
    ]
  }

  statement {
    sid = "ManageVpcNetworkInterfaces"
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
    sid       = "AllowCodeBuildNetworkInterfacePermission"
    actions   = ["ec2:CreateNetworkInterfacePermission"]
    resources = ["arn:aws:ec2:us-east-1:*:network-interface/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:AuthorizedService"
      values   = ["codebuild.amazonaws.com"]
    }

    condition {
      test     = "ArnEquals"
      variable = "ec2:Subnet"
      values   = [aws_subnet.autograder.arn]
    }
  }
}

resource "aws_s3_bucket" "results" {
  bucket_prefix = "${var.project_name}-results-"
}

resource "aws_vpc" "autograder" {
  cidr_block           = "10.40.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "autograder" {
  vpc_id            = aws_vpc.autograder.id
  cidr_block        = "10.40.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "${var.project_name}-private-subnet"
  }
}

resource "aws_security_group" "codebuild" {
  name        = "${var.project_name}-codebuild"
  description = "No internet egress for autograder builds"
  vpc_id      = aws_vpc.autograder.id

  tags = {
    Name = "${var.project_name}-codebuild-sg"
  }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.autograder.id
  service_name      = "com.amazonaws.us-east-1.s3"
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
  description  = "Runs CS autograder submissions from GitHub without internet egress and stores results in S3."
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
    location  = var.github_repo_url
    buildspec = <<-EOT
      version: 0.2
      phases:
        build:
          commands:
            - ./run-autograder.sh
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

  depends_on = [
    aws_iam_role_policy_attachment.codebuild,
    aws_vpc_endpoint.s3
  ]
}

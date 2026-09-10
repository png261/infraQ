resource "aws_s3_bucket" "codebuild_output" {
  bucket_prefix = "students-codebuild-output-"
}

resource "aws_vpc" "codebuild" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "codebuild" {
  vpc_id     = aws_vpc.codebuild.id
  cidr_block = "10.0.0.0/24"
}

resource "aws_security_group" "codebuild" {
  name_prefix = "codebuild-no-internet-"
  description = "Security group for CodeBuild with no ingress or egress"
  vpc_id      = aws_vpc.codebuild.id

  ingress = []
  egress  = []
}

data "aws_iam_policy_document" "codebuild_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name_prefix        = "students-codebuild-"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role.json
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]

    resources = ["*"]
  }

  statement {
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket"
    ]

    resources = [aws_s3_bucket.codebuild_output.arn]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject"
    ]

    resources = ["${aws_s3_bucket.codebuild_output.arn}/*"]
  }

  statement {
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
    actions = ["ec2:CreateNetworkInterfacePermission"]

    resources = ["arn:aws:ec2:us-east-1:*:network-interface/*"]

    condition {
      test     = "StringEquals"
      variable = "ec2:Subnet"
      values   = [aws_subnet.codebuild.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "ec2:AuthorizedService"
      values   = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "codebuild" {
  name_prefix = "students-codebuild-"
  policy      = data.aws_iam_policy_document.codebuild.json
}

resource "aws_iam_role_policy_attachment" "codebuild" {
  role       = aws_iam_role.codebuild.name
  policy_arn = aws_iam_policy.codebuild.arn
}

resource "aws_codebuild_project" "students" {
  name         = "students-codebuild-project"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type     = "S3"
    location = aws_s3_bucket.codebuild_output.bucket
    name     = "students-codebuild-output"
  }

  environment {
    compute_type = "BUILD_GENERAL1_SMALL"
    image        = "alpine"
    type         = "LINUX_CONTAINER"
  }

  source {
    type            = "GITHUB"
    git_clone_depth = 1
    location        = "github.com/source-location"
  }

  vpc_config {
    vpc_id             = aws_vpc.codebuild.id
    subnets            = [aws_subnet.codebuild.id]
    security_group_ids = [aws_security_group.codebuild.id]
  }
}

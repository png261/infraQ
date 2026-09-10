resource "aws_s3_bucket" "codebuild_output" {
  bucket_prefix = "student-codebuild-output-"
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
  name_prefix        = "student-codebuild-"
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
      "s3:PutObject"
    ]

    resources = ["${aws_s3_bucket.codebuild_output.arn}/*"]
  }
}

resource "aws_iam_policy" "codebuild" {
  name_prefix = "student-codebuild-"
  policy      = data.aws_iam_policy_document.codebuild.json
}

resource "aws_iam_role_policy_attachment" "codebuild" {
  role       = aws_iam_role.codebuild.name
  policy_arn = aws_iam_policy.codebuild.arn
}

resource "aws_codebuild_project" "student_output" {
  name         = "student-codebuild-output"
  service_role = aws_iam_role.codebuild.arn

  artifacts {
    type     = "S3"
    location = aws_s3_bucket.codebuild_output.bucket
    name     = "student-codebuild-output"
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
}

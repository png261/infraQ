data "aws_iam_policy_document" "sagemaker_image_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "sagemaker_image_execution" {
  name               = "sagemaker-image-execution-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_image_assume_role.json

  tags = {
    Name = "sagemaker-image-execution-role"
  }
}

resource "aws_sagemaker_image" "example" {
  image_name = "example-sagemaker-image"
  role_arn   = aws_iam_role.sagemaker_image_execution.arn

  tags = {
    Name = "example-sagemaker-image"
  }
}

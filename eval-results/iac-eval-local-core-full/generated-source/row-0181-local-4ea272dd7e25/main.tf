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

resource "aws_iam_role" "sagemaker_pipeline" {
  name               = var.role_name
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role.json
}

data "aws_sagemaker_prebuilt_ecr_image" "sklearn" {
  repository_name = "sagemaker-scikit-learn"
  image_tag       = "1.2-1-cpu-py3"
}

resource "aws_sagemaker_pipeline" "this" {
  pipeline_name         = var.pipeline_name
  role_arn              = aws_iam_role.sagemaker_pipeline.arn
  pipeline_display_name = var.pipeline_name
  pipeline_description  = "Minimal SageMaker Pipeline managed by Terraform/OpenTofu."

  pipeline_definition = jsonencode({
    Version = "2020-12-01"
    Metadata = {
      PrebuiltImageUri = data.aws_sagemaker_prebuilt_ecr_image.sklearn.registry_path
    }
    Parameters = []
    Steps      = []
  })
}

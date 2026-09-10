locals {
  name_prefix = "iac-eval-sagemaker"
}

data "aws_iam_policy_document" "sagemaker_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "sagemaker_model_artifact_access" {
  statement {
    actions = [
      "s3:GetObject",
    ]

    resources = [
      aws_s3_object.model_artifact.arn,
    ]
  }
}

resource "aws_iam_role" "sagemaker_execution" {
  name               = "${local.name_prefix}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role.json
}

resource "aws_iam_role_policy" "sagemaker_model_artifact_access" {
  name   = "${local.name_prefix}-model-artifact-access"
  role   = aws_iam_role.sagemaker_execution.id
  policy = data.aws_iam_policy_document.sagemaker_model_artifact_access.json
}

resource "aws_s3_bucket" "model_artifacts" {
  bucket_prefix = "${local.name_prefix}-"
  force_destroy = true
}

resource "aws_s3_object" "model_artifact" {
  bucket = aws_s3_bucket.model_artifacts.id
  key    = "model/model.tar.gz"

  # Minimal gzip-compressed tar archive so the SageMaker model has a concrete
  # artifact location for endpoint configuration deployment.
  content_base64 = "H4sIAAAAAAAAA+3BMQEAAADCoPVPbQwfoAAAAAAAAAAAAAAAAAAAAAAA4I0BcKx1xgAoAAA="
  content_type   = "application/gzip"
}

data "aws_sagemaker_prebuilt_ecr_image" "xgboost" {
  repository_name = "sagemaker-xgboost"
  image_tag       = "1.5-1"
}

resource "aws_sagemaker_model" "example" {
  name               = "${local.name_prefix}-model"
  execution_role_arn = aws_iam_role.sagemaker_execution.arn

  primary_container {
    image          = data.aws_sagemaker_prebuilt_ecr_image.xgboost.registry_path
    model_data_url = "s3://${aws_s3_bucket.model_artifacts.id}/${aws_s3_object.model_artifact.key}"
  }

  depends_on = [
    aws_iam_role_policy.sagemaker_model_artifact_access,
  ]
}

resource "aws_sagemaker_endpoint_configuration" "example" {
  name = "${local.name_prefix}-endpoint-config"

  production_variants {
    variant_name           = "AllTraffic"
    model_name             = aws_sagemaker_model.example.name
    initial_instance_count = 1
    instance_type          = "ml.t2.medium"
    initial_variant_weight = 1
  }
}

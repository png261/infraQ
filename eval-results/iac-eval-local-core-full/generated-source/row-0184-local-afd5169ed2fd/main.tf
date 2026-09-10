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

resource "aws_iam_role" "sagemaker_execution" {
  name               = "${var.name_prefix}-execution-role"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume_role.json
}

data "aws_iam_policy_document" "sagemaker_model_artifact" {
  statement {
    sid    = "ReadModelArtifact"
    effect = "Allow"

    actions = [
      "s3:GetObject"
    ]

    resources = [
      aws_s3_object.model_artifact.arn
    ]
  }
}

resource "aws_iam_role_policy" "sagemaker_model_artifact" {
  name   = "${var.name_prefix}-model-artifact-read"
  role   = aws_iam_role.sagemaker_execution.id
  policy = data.aws_iam_policy_document.sagemaker_model_artifact.json
}

resource "aws_s3_bucket" "model_artifacts" {
  bucket_prefix = "${var.name_prefix}-model-"
}

resource "aws_s3_object" "model_artifact" {
  bucket       = aws_s3_bucket.model_artifacts.id
  key          = "model.tar.gz"
  content_type = "application/gzip"

  # A checked-in, non-empty SageMaker XGBoost model artifact. The archive
  # contains an XGBoost Booster saved as xgboost-model, which is the filename
  # the SageMaker prebuilt XGBoost inference container loads by default.
  # The content is kept in a separate base64 file so the Terraform resource has
  # an explicit source hash and does not rely on an inline placeholder archive.
  content_base64 = file("${path.module}/model/model.tar.gz.base64")
  source_hash    = filesha256("${path.module}/model/model.tar.gz.base64")
}

data "aws_sagemaker_prebuilt_ecr_image" "inference" {
  repository_name = var.sagemaker_image_repository_name
  image_tag       = var.sagemaker_image_tag
}

resource "aws_sagemaker_model" "this" {
  name               = "${var.name_prefix}-model"
  execution_role_arn = aws_iam_role.sagemaker_execution.arn

  primary_container {
    image          = data.aws_sagemaker_prebuilt_ecr_image.inference.registry_path
    model_data_url = "s3://${aws_s3_bucket.model_artifacts.id}/${aws_s3_object.model_artifact.key}"
  }

  depends_on = [aws_iam_role_policy.sagemaker_model_artifact]
}

resource "aws_sagemaker_endpoint_configuration" "this" {
  name = "${var.name_prefix}-endpoint-config"

  production_variants {
    variant_name           = "AllTraffic"
    model_name             = aws_sagemaker_model.this.name
    initial_instance_count = var.initial_instance_count
    instance_type          = var.instance_type
  }
}

resource "aws_sagemaker_endpoint" "this" {
  name                 = "${var.name_prefix}-endpoint"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.this.name
}

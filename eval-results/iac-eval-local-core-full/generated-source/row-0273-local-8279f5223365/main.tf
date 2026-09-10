resource "aws_s3_bucket" "source" {
  bucket = "mybucket"
}

resource "aws_s3_bucket" "inventory_destination" {
  bucket = "mybucket-inventory-destination"
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "inventory_destination" {
  statement {
    sid = "AllowS3InventoryDelivery"

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    actions = ["s3:PutObject"]

    resources = ["${aws_s3_bucket.inventory_destination.arn}/inventory/*"]

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.source.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

resource "aws_s3_bucket_policy" "inventory_destination" {
  bucket = aws_s3_bucket.inventory_destination.id
  policy = data.aws_iam_policy_document.inventory_destination.json
}

resource "aws_s3_bucket_inventory" "daily" {
  bucket = aws_s3_bucket.source.id
  name   = "daily-inventory"

  included_object_versions = "All"

  destination {
    bucket {
      bucket_arn = aws_s3_bucket.inventory_destination.arn
      format     = "CSV"
      prefix     = "inventory/"
    }
  }

  schedule {
    frequency = "Daily"
  }

  depends_on = [aws_s3_bucket_policy.inventory_destination]
}

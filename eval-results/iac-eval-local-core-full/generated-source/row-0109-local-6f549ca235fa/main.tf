resource "aws_s3_bucket" "platform_infra" {
  bucket = "wellcomecollection-platform-infra"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "platform_infra" {
  bucket = aws_s3_bucket.platform_infra.id

  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "platform_infra" {
  bucket = aws_s3_bucket.platform_infra.id
  acl    = "private"

  depends_on = [aws_s3_bucket_ownership_controls.platform_infra]
}

resource "aws_s3_bucket_versioning" "platform_infra" {
  bucket = aws_s3_bucket.platform_infra.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "platform_infra" {
  bucket = aws_s3_bucket.platform_infra.id

  rule {
    id     = "tmp-prefix-expiration"
    status = "Enabled"

    filter {
      prefix = "tmp/"
    }

    expiration {
      days = 30
    }
  }

  rule {
    id     = "old-version-retention"
    status = "Enabled"

    filter {
      prefix = ""
    }

    noncurrent_version_transition {
      noncurrent_days = 30
      storage_class   = "STANDARD_IA"
    }

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  depends_on = [aws_s3_bucket_versioning.platform_infra]
}

resource "aws_s3_bucket" "source" {
  bucket_prefix = "iac-eval-inventory-source-"
}

resource "aws_s3_bucket" "destination" {
  bucket_prefix = "iac-eval-inventory-destination-"
}

resource "aws_s3_bucket_inventory" "weekly_current_versions" {
  bucket = aws_s3_bucket.source.id
  name   = "weekly-current-versions"

  included_object_versions = "Current"

  schedule {
    frequency = "Weekly"
  }

  destination {
    bucket {
      bucket_arn = aws_s3_bucket.destination.arn
      format     = "CSV"
    }
  }
}

resource "aws_s3_bucket" "source" {
  bucket = "mybucket"
}

resource "aws_s3_bucket" "analytics_destination" {
  bucket = "mybucket-analytics-destination"
}

resource "aws_s3_bucket_analytics_configuration" "source" {
  bucket = aws_s3_bucket.source.id
  name   = "EntireBucketAnalytics"

  storage_class_analysis {
    data_export {
      output_schema_version = "V_1"

      destination {
        s3_bucket_destination {
          bucket_arn = aws_s3_bucket.analytics_destination.arn
          format     = "CSV"
        }
      }
    }
  }
}

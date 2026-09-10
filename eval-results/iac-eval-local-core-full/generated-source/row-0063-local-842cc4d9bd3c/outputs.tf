output "delivery_stream_name" {
  description = "Name of the Kinesis Data Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.splunk.name
}

output "backup_bucket_name" {
  description = "Name of the S3 backup bucket."
  value       = aws_s3_bucket.firehose_backup.bucket
}

output "firehose_role_arn" {
  description = "ARN of the IAM role assumed by Kinesis Data Firehose."
  value       = aws_iam_role.firehose_delivery.arn
}

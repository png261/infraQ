output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.redshift.name
}

output "redshift_cluster_endpoint" {
  description = "Endpoint address of the Redshift cluster."
  value       = aws_redshift_cluster.destination.endpoint
}

output "s3_backup_bucket_name" {
  description = "S3 bucket used by Firehose for intermediate delivery and failed record backup."
  value       = aws_s3_bucket.firehose_backup.bucket
}

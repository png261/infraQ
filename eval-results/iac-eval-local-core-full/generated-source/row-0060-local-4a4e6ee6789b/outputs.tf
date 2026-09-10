output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.redshift.name
}

output "redshift_cluster_identifier" {
  description = "Identifier of the Redshift destination cluster."
  value       = aws_redshift_cluster.destination.cluster_identifier
}

output "staging_bucket_name" {
  description = "Name of the S3 staging bucket used by Firehose."
  value       = aws_s3_bucket.firehose_staging.bucket
}

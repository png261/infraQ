output "firehose_delivery_stream_name" {
  description = "Name of the Kinesis Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.elasticsearch.name
}

output "elasticsearch_domain_name" {
  description = "Name of the Elasticsearch domain."
  value       = aws_elasticsearch_domain.destination.domain_name
}

output "backup_bucket_name" {
  description = "Name of the S3 bucket used for Firehose backup delivery."
  value       = aws_s3_bucket.firehose_backup.bucket
}

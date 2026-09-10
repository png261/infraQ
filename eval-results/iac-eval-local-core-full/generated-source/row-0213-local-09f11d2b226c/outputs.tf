output "msk_cluster_arn" {
  description = "ARN of the managed MSK cluster."
  value       = aws_msk_cluster.main.arn
}

output "msk_bootstrap_brokers" {
  description = "Plaintext bootstrap brokers used by the MSK Connect connector."
  value       = aws_msk_cluster.main.bootstrap_brokers
}

output "custom_plugin_arn" {
  description = "ARN of the Debezium MSK Connect custom plugin."
  value       = aws_mskconnect_custom_plugin.debezium.arn
}

output "connector_arn" {
  description = "ARN of the MSK Connect connector."
  value       = aws_mskconnect_connector.debezium.arn
}

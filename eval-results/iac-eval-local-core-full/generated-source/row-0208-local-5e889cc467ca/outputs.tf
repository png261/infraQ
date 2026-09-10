output "msk_serverless_cluster_arn" {
  description = "ARN of the benchmark MSK Serverless cluster."
  value       = aws_msk_serverless_cluster.benchmark.arn
}

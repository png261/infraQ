output "cluster_name" {
  description = "Name of the EKS cluster."
  value       = aws_eks_cluster.cluster.name
}

output "cluster_endpoint" {
  description = "Endpoint for the EKS cluster API server."
  value       = aws_eks_cluster.cluster.endpoint
}

output "vpc_id" {
  description = "ID of the VPC used by the EKS cluster."
  value       = aws_vpc.main.id
}

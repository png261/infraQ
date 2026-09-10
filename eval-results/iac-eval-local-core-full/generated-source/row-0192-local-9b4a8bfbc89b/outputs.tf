output "placement_group_name" {
  description = "Name of the EC2 cluster placement group."
  value       = aws_placement_group.cluster.name
}

output "instance_ids" {
  description = "IDs of the EC2 instances in the cluster placement group."
  value       = aws_instance.cluster[*].id
}

output "vpc_id" {
  description = "ID of the VPC containing the placement group instances."
  value       = aws_vpc.cluster.id
}

output "subnet_ids" {
  description = "IDs of the two subnets created for the benchmark."
  value = [
    aws_subnet.cluster_a.id,
    aws_subnet.cluster_b.id,
  ]
}

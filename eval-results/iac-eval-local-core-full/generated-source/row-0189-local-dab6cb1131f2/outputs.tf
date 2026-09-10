output "vpc_id" {
  description = "ID of the benchmark VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public subnet."
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID of the private subnet."
  value       = aws_subnet.private.id
}

output "amazon_linux_2_ami_id" {
  description = "Newest Amazon Linux 2 AMI selected for us-east-1."
  value       = data.aws_ami.amazon_linux_2.id
}

output "launch_template_id" {
  description = "ID of the launch template used by the EC2 Fleet and Auto Scaling Group."
  value       = aws_launch_template.main.id
}

output "ec2_fleet_id" {
  description = "ID of the EC2 Fleet targeting 5 On-Demand and 4 Spot instances."
  value       = aws_ec2_fleet.main.id
}

output "autoscaling_group_name" {
  description = "Name of the Auto Scaling Group."
  value       = aws_autoscaling_group.main.name
}

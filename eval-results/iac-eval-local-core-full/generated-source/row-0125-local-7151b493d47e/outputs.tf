output "source_amazon_linux_2_ami_id" {
  description = "AMI ID selected as the latest Amazon Linux 2 source image."
  value       = data.aws_ami.amazon_linux_2.id
}

output "registered_ami_id" {
  description = "ID of the AMI registered from the latest Amazon Linux 2 root snapshot."
  value       = aws_ami.latest_amazon_linux_2.id
}

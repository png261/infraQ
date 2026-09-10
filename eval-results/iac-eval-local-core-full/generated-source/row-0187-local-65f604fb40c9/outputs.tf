output "amazon_linux_2_ami_name" {
  description = "Name assigned to the benchmark AMI resource."
  value       = aws_ami.latest_amazon_linux_2.name
}

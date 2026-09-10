output "lightsail_instance_name" {
  description = "Name of the Lightsail instance used as the distribution origin."
  value       = aws_lightsail_instance.origin.name
}

output "lightsail_static_ip_name" {
  description = "Name of the Lightsail static IP attached to the origin instance."
  value       = aws_lightsail_static_ip.origin.name
}

output "lightsail_distribution_name" {
  description = "Name of the Lightsail distribution."
  value       = aws_lightsail_distribution.origin.name
}

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public subnet hosting the web server."
  value       = aws_subnet.public.id
}

output "private_app_subnet_id" {
  description = "ID of the private subnet hosting the application server."
  value       = aws_subnet.private_app.id
}

output "private_db_subnet_id" {
  description = "ID of the private subnet hosting the database."
  value       = aws_subnet.private_db.id
}

output "web_instance_id" {
  description = "ID of the public web EC2 instance."
  value       = aws_instance.web.id
}

output "app_instance_id" {
  description = "ID of the private application EC2 instance."
  value       = aws_instance.app.id
}

output "database_endpoint" {
  description = "RDS database endpoint."
  value       = aws_db_instance.database.endpoint
}

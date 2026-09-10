output "vpc_id" {
  description = "ID of the benchmark VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID of the public web subnet."
  value       = aws_subnet.public_web.id
}

output "private_subnet_ids" {
  description = "IDs of the private application and database subnets."
  value       = [aws_subnet.private_app.id, aws_subnet.private_db.id]
}

output "web_instance_id" {
  description = "ID of the public webserver EC2 instance."
  value       = aws_instance.web.id
}

output "app_instance_id" {
  description = "ID of the private application EC2 instance."
  value       = aws_instance.app.id
}

output "database_endpoint" {
  description = "Endpoint of the private relational database."
  value       = aws_db_instance.database.endpoint
}

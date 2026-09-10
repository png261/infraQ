output "route53_record_name" {
  description = "DNS record that points to the Elastic Beanstalk environment."
  value       = aws_route53_record.app.fqdn
}

output "elastic_beanstalk_environment_cname" {
  description = "Elastic Beanstalk environment CNAME target."
  value       = aws_elastic_beanstalk_environment.myenv.cname
}

output "rds_address" {
  description = "RDS database address."
  value       = aws_db_instance.myapp_db.address
}

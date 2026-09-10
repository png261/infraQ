output "elastic_beanstalk_environment_names" {
  description = "Names of the Elastic Beanstalk environments."
  value = [
    aws_elastic_beanstalk_environment.web.name,
    aws_elastic_beanstalk_environment.worker.name,
  ]
}

output "rds_endpoint_address" {
  description = "Address of the RDS instance used by the Elastic Beanstalk environments."
  value       = aws_db_instance.app.address
}

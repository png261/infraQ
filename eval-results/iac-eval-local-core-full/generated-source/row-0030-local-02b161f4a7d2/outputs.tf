output "elastic_beanstalk_application_name" {
  description = "Name of the Elastic Beanstalk application."
  value       = aws_elastic_beanstalk_application.web.name
}

resource "aws_elastic_beanstalk_application" "web" {
  name        = "supported-language-web-application"
  description = "Elastic Beanstalk application for deploying and scaling a supported-language web application."
}

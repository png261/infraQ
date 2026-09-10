resource "aws_elastic_beanstalk_application" "app" {
  name = "benchmark-elastic-beanstalk-app"
}

resource "aws_elastic_beanstalk_configuration_template" "template" {
  name                = "benchmark-elastic-beanstalk-template"
  application         = aws_elastic_beanstalk_application.app.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.6.1 running Docker"
}

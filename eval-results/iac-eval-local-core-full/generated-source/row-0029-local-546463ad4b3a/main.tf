resource "aws_elastic_beanstalk_application" "go_app" {
  name = "go-elastic-beanstalk-app"
}

resource "aws_elastic_beanstalk_configuration_template" "go_template" {
  name                = "go-elastic-beanstalk-template"
  application         = aws_elastic_beanstalk_application.go_app.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.0.4 running Go 1"
}

data "aws_elastic_beanstalk_solution_stack" "blue" {
  most_recent = true
  name_regex  = "^64bit Amazon Linux 2023 .* running Corretto 17$"
}

data "aws_elastic_beanstalk_solution_stack" "green" {
  provider    = aws.green
  most_recent = true
  name_regex  = "^64bit Amazon Linux 2023 .* running Corretto 17$"
}

data "aws_iam_policy_document" "elastic_beanstalk_ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "elastic_beanstalk_ec2" {
  name               = "elastic-beanstalk-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.elastic_beanstalk_ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "web_tier" {
  role       = aws_iam_role.elastic_beanstalk_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_instance_profile" "elastic_beanstalk_ec2" {
  name = "elastic-beanstalk-ec2-instance-profile"
  role = aws_iam_role.elastic_beanstalk_ec2.name
}

resource "aws_elastic_beanstalk_application" "blue" {
  name = "blue-green-application"
}

resource "aws_elastic_beanstalk_application" "green" {
  provider = aws.green
  name     = "blue-green-application"
}

resource "aws_elastic_beanstalk_environment" "blue" {
  name                = "blue"
  application         = aws_elastic_beanstalk_application.blue.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.blue.name

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.elastic_beanstalk_ec2.name
  }
}

resource "aws_elastic_beanstalk_environment" "green" {
  provider            = aws.green
  name                = "green"
  application         = aws_elastic_beanstalk_application.green.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.green.name

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.elastic_beanstalk_ec2.name
  }
}

resource "aws_route53_zone" "blue_green" {
  name = "example-blue-green.com"
}

resource "aws_route53_record" "blue" {
  zone_id = aws_route53_zone.blue_green.zone_id
  name    = "app.${aws_route53_zone.blue_green.name}"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "blue"

  weighted_routing_policy {
    weight = 50
  }

  records = [aws_elastic_beanstalk_environment.blue.cname]
}

resource "aws_route53_record" "green" {
  provider = aws.green
  zone_id  = aws_route53_zone.blue_green.zone_id
  name     = "app.${aws_route53_zone.blue_green.name}"
  type     = "CNAME"
  ttl      = 60

  set_identifier = "green"

  weighted_routing_policy {
    weight = 50
  }

  records = [aws_elastic_beanstalk_environment.green.cname]
}

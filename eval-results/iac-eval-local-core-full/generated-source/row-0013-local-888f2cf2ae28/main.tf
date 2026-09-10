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

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_web_tier" {
  role       = aws_iam_role.elastic_beanstalk_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_instance_profile" "elastic_beanstalk" {
  name = "elastic-beanstalk-instance-profile"
  role = aws_iam_role.elastic_beanstalk_ec2.name
}

resource "aws_elastic_beanstalk_application" "us_west" {
  provider = aws.us_west
  name     = "us_west"
}

resource "aws_elastic_beanstalk_application" "eu_central" {
  provider = aws.eu_central
  name     = "eu_central"
}

resource "aws_elastic_beanstalk_environment" "us_west" {
  provider            = aws.us_west
  name                = "us_west"
  application         = aws_elastic_beanstalk_application.us_west.name
  solution_stack_name = "64bit Amazon Linux 2023 v6.4.0 running Node.js 20"

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.elastic_beanstalk.name
  }
}

resource "aws_elastic_beanstalk_environment" "eu_central" {
  provider            = aws.eu_central
  name                = "eu_central"
  application         = aws_elastic_beanstalk_application.eu_central.name
  solution_stack_name = "64bit Amazon Linux 2023 v6.4.0 running Node.js 20"

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.elastic_beanstalk.name
  }
}

resource "aws_route53_zone" "primary" {
  name = "example.com"
}

resource "aws_route53_record" "us_west" {
  name    = "app.example.com"
  type    = "CNAME"
  ttl     = 60
  zone_id = aws_route53_zone.primary.zone_id

  geolocation_routing_policy {
    continent = "NA"
  }

  set_identifier = "us_west"
  records        = [aws_elastic_beanstalk_environment.us_west.cname]
}

resource "aws_route53_record" "eu_central" {
  name    = "app.example.com"
  type    = "CNAME"
  ttl     = 60
  zone_id = aws_route53_zone.primary.zone_id

  geolocation_routing_policy {
    continent = "EU"
  }

  set_identifier = "eu_central"
  records        = [aws_elastic_beanstalk_environment.eu_central.cname]
}

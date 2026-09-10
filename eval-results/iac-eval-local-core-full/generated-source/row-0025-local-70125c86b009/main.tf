data "aws_iam_policy_document" "eb_ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eb_ec2_role" {
  name               = "eb_ec2_role3"
  assume_role_policy = data.aws_iam_policy_document.eb_ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "eb_web_tier" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_instance_profile" "eb_ec2_profile3" {
  name = "eb_ec2_profile3"
  role = aws_iam_role.eb_ec2_role.name
}

resource "aws_db_instance" "main_db_us_east" {
  provider = aws.us_east_1

  identifier              = "main-db-us-east"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  engine                  = "mysql"
  username                = var.db_username
  password                = var.db_password
  backup_retention_period = 1
  skip_final_snapshot     = true
}

resource "aws_db_instance" "main_db_eu_west" {
  provider = aws.eu_west_1

  identifier              = "main-db-eu-west"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  engine                  = "mysql"
  username                = var.db_username
  password                = var.db_password
  backup_retention_period = 1
  skip_final_snapshot     = true
}

resource "aws_elastic_beanstalk_application" "myapp_us_east" {
  provider = aws.us_east_1

  name = "myapp_us_east"
}

resource "aws_elastic_beanstalk_application" "myapp_eu_west" {
  provider = aws.eu_west_1

  name = "myapp_eu_west"
}

resource "aws_elastic_beanstalk_environment" "myenv_us_east" {
  provider = aws.us_east_1

  name                = "myenv_us_east"
  application         = aws_elastic_beanstalk_application.myapp_us_east.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.5.0 running Docker"

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_ec2_profile3.name
  }

  dynamic "setting" {
    for_each = var.eb_service_role_name == null ? [] : [var.eb_service_role_name]

    content {
      namespace = "aws:elasticbeanstalk:environment"
      name      = "ServiceRole"
      value     = setting.value
    }
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_HOST"
    value     = aws_db_instance.main_db_us_east.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_USERNAME"
    value     = aws_db_instance.main_db_us_east.username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_PASSWORD"
    value     = aws_db_instance.main_db_us_east.password
  }
}

resource "aws_elastic_beanstalk_environment" "myenv_eu_west" {
  provider = aws.eu_west_1

  name                = "myenv_eu_west"
  application         = aws_elastic_beanstalk_application.myapp_eu_west.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.5.0 running Docker"

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_ec2_profile3.name
  }

  dynamic "setting" {
    for_each = var.eb_service_role_name == null ? [] : [var.eb_service_role_name]

    content {
      namespace = "aws:elasticbeanstalk:environment"
      name      = "ServiceRole"
      value     = setting.value
    }
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_HOST"
    value     = aws_db_instance.main_db_eu_west.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_USERNAME"
    value     = aws_db_instance.main_db_eu_west.username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_PASSWORD"
    value     = aws_db_instance.main_db_eu_west.password
  }
}

resource "aws_route53_zone" "primary" {
  name = var.domain_name
}

resource "aws_route53_record" "us_east" {
  provider = aws.us_east_1

  zone_id        = aws_route53_zone.primary.zone_id
  name           = var.domain_name
  type           = "CNAME"
  ttl            = 60
  set_identifier = "us-east-1"
  records        = [aws_elastic_beanstalk_environment.myenv_us_east.cname]

  latency_routing_policy {
    region = "us-east-1"
  }
}

resource "aws_route53_record" "eu_west" {
  provider = aws.eu_west_1

  zone_id        = aws_route53_zone.primary.zone_id
  name           = var.domain_name
  type           = "CNAME"
  ttl            = 60
  set_identifier = "eu-west-1"
  records        = [aws_elastic_beanstalk_environment.myenv_eu_west.cname]

  latency_routing_policy {
    region = "eu-west-1"
  }
}

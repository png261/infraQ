resource "aws_iam_role" "eb_ec2_role" {
  name = "ec2-eb-role1"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eb_web_tier" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_instance_profile" "ec2_eb_profile1" {
  name = "ec2_eb_profile1"
  role = aws_iam_role.eb_ec2_role.name
}

resource "aws_elastic_beanstalk_application" "app" {
  name = "blue-green-rds-app"
}

data "aws_elastic_beanstalk_solution_stack" "python" {
  most_recent = true
  name_regex  = "^64bit Amazon Linux .* running Python .*$"
}

resource "aws_db_instance" "my_db" {
  identifier                = "my-db"
  instance_class            = "db.t3.micro"
  allocated_storage         = 20
  engine                    = "mysql"
  username                  = "adminuser"
  password                  = "ChangeMe123!"
  skip_final_snapshot       = false
  final_snapshot_identifier = "my-db-final-snapshot"
  multi_az                  = true
  backup_retention_period   = 7
}

resource "aws_db_snapshot" "pre_deployment" {
  db_instance_identifier = aws_db_instance.my_db.identifier
  db_snapshot_identifier = "my-db-pre-deployment-snapshot"
}

resource "aws_elastic_beanstalk_environment" "blue" {
  name                = "blue-environment"
  application         = aws_elastic_beanstalk_application.app.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.python.name

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.ec2_eb_profile1.name
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_HOSTNAME"
    value     = aws_db_instance.my_db.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_USERNAME"
    value     = aws_db_instance.my_db.username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_PASSWORD"
    value     = aws_db_instance.my_db.password
  }
}

resource "aws_elastic_beanstalk_environment" "green" {
  name                = "green-environment"
  application         = aws_elastic_beanstalk_application.app.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.python.name

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.ec2_eb_profile1.name
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_HOSTNAME"
    value     = aws_db_instance.my_db.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_USERNAME"
    value     = aws_db_instance.my_db.username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_PASSWORD"
    value     = aws_db_instance.my_db.password
  }
}

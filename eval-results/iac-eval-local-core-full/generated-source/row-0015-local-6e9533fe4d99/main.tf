terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_iam_role" "eb_ec2_role" {
  name = "eb_ec2_role"

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

resource "aws_iam_instance_profile" "eb_ec2_profile" {
  name = "eb_ec2_profile"
  role = aws_iam_role.eb_ec2_role.name
}

resource "aws_elastic_beanstalk_application" "app" {
  name = "benchmark-eb-app"
}

resource "aws_db_instance" "prod_db" {
  identifier              = "production"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  engine                  = "mysql"
  engine_version          = "8.0"
  db_name                 = "prod_db"
  username                = "prod_admin"
  password                = "ProdDbPassword123!"
  backup_retention_period = 7
  skip_final_snapshot     = true
}

resource "aws_db_instance" "staging_db" {
  identifier              = "staging"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  engine                  = "mysql"
  engine_version          = "8.0"
  db_name                 = "staging_db"
  username                = "staging_admin"
  password                = "StagingDbPassword123!"
  backup_retention_period = 7
  skip_final_snapshot     = true
}

resource "aws_elastic_beanstalk_environment" "production" {
  name                = "production"
  application         = aws_elastic_beanstalk_application.app.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.3.0 running Docker"

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_ec2_profile.name
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_HOST"
    value     = aws_db_instance.prod_db.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_USERNAME"
    value     = aws_db_instance.prod_db.username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_PASSWORD"
    value     = aws_db_instance.prod_db.password
  }
}

resource "aws_elastic_beanstalk_environment" "staging" {
  name                = "staging"
  application         = aws_elastic_beanstalk_application.app.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.3.0 running Docker"

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_ec2_profile.name
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_HOST"
    value     = aws_db_instance.staging_db.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_USERNAME"
    value     = aws_db_instance.staging_db.username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_PASSWORD"
    value     = aws_db_instance.staging_db.password
  }
}

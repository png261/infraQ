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

variable "db_username" {
  description = "Master username for the shared RDS database."
  type        = string
  default     = "myappadmin"
}

variable "db_password" {
  description = "Master password for the shared RDS database. Provide a strong value at plan/apply time."
  type        = string
  sensitive   = true
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

resource "aws_elastic_beanstalk_application" "myapp" {
  name = "myapp"
}

resource "aws_db_instance" "myapp_db" {
  identifier              = "myapp-db"
  db_name                 = "myapp_db"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  engine                  = "mysql"
  username                = var.db_username
  password                = var.db_password
  backup_retention_period = 7
  skip_final_snapshot     = true
}

resource "aws_elastic_beanstalk_environment" "blue" {
  name                = "blue"
  application         = aws_elastic_beanstalk_application.myapp.name
  solution_stack_name = "64bit Amazon Linux 2023 v6.4.2 running Node.js 20"

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_ec2_profile.name
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_HOST"
    value     = aws_db_instance.myapp_db.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_USERNAME"
    value     = aws_db_instance.myapp_db.username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_PASSWORD"
    value     = aws_db_instance.myapp_db.password
  }
}

resource "aws_elastic_beanstalk_environment" "green" {
  name                = "green"
  application         = aws_elastic_beanstalk_application.myapp.name
  solution_stack_name = "64bit Amazon Linux 2023 v6.4.2 running Node.js 20"

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_ec2_profile.name
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_HOST"
    value     = aws_db_instance.myapp_db.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_USERNAME"
    value     = aws_db_instance.myapp_db.username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_PASSWORD"
    value     = aws_db_instance.myapp_db.password
  }
}

resource "aws_route53_zone" "myapp" {
  name = "example.com"
}

resource "aws_route53_health_check" "blue" {
  fqdn              = aws_db_instance.myapp_db.address
  type              = "TCP"
  port              = 3306
  failure_threshold = 3
}

resource "aws_route53_health_check" "green" {
  fqdn              = aws_db_instance.myapp_db.address
  type              = "TCP"
  port              = 3306
  failure_threshold = 3
}

resource "aws_route53_record" "blue" {
  zone_id         = aws_route53_zone.myapp.zone_id
  name            = "app.example.com"
  type            = "CNAME"
  ttl             = 60
  set_identifier  = "blue-primary"
  records         = [aws_elastic_beanstalk_environment.blue.cname]
  health_check_id = aws_route53_health_check.blue.id

  failover_routing_policy {
    type = "PRIMARY"
  }
}

resource "aws_route53_record" "green" {
  zone_id         = aws_route53_zone.myapp.zone_id
  name            = "app.example.com"
  type            = "CNAME"
  ttl             = 60
  set_identifier  = "green-secondary"
  records         = [aws_elastic_beanstalk_environment.green.cname]
  health_check_id = aws_route53_health_check.green.id

  failover_routing_policy {
    type = "SECONDARY"
  }
}

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type        = string
  description = "AWS region to deploy resources into."
  default     = "us-east-1"
}

variable "db_username" {
  type        = string
  description = "Master username for the RDS database."
  default     = "adminuser"
}

variable "db_password" {
  type        = string
  description = "Master password for the RDS database."
  default     = "ChangeMe12345!"
  sensitive   = true
}

variable "beanstalk_app_name" {
  type        = string
  description = "Elastic Beanstalk application name."
  default     = "cpu-autoscale-eb-app"
}

variable "beanstalk_env_name" {
  type        = string
  description = "Elastic Beanstalk environment name."
  default     = "cpu-autoscale-eb-env"
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_iam_policy_document" "eb_ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eb_ec2_role" {
  name               = "eb_ec2_role"
  assume_role_policy = data.aws_iam_policy_document.eb_ec2_assume_role.json
}

resource "aws_iam_role_policy_attachment" "eb_web_tier" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_role_policy_attachment" "eb_worker_tier" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier"
}

resource "aws_iam_role_policy_attachment" "eb_multicontainer_docker" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
}

resource "aws_iam_instance_profile" "eb_ec2_profile" {
  name = "eb_ec2_profile"
  role = aws_iam_role.eb_ec2_role.name
}

data "aws_iam_policy_document" "eb_service_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["elasticbeanstalk.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "eb_service_role" {
  name               = "eb_service_role"
  assume_role_policy = data.aws_iam_policy_document.eb_service_assume_role.json
}

resource "aws_iam_role_policy_attachment" "eb_service_role_enhanced_health" {
  role       = aws_iam_role.eb_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_iam_role_policy_attachment" "eb_service_role_managed_updates" {
  role       = aws_iam_role.eb_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy"
}

resource "aws_security_group" "eb_instance_sg" {
  name        = "eb-instance-sg"
  description = "Security group for Elastic Beanstalk EC2 instances"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow HTTP inbound traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS inbound traffic"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_sg" {
  name        = "my-db1-rds-sg"
  description = "Security group for RDS database my_db1"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Allow MySQL access from Elastic Beanstalk instances"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.eb_instance_sg.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_subnet_group" "my_db1" {
  name       = "my-db1-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "my-db1-subnet-group"
  }
}

resource "aws_db_instance" "my_db1" {
  identifier             = "my-db1"
  db_name                = "my_db1"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  storage_type           = "gp2"
  username               = var.db_username
  password               = var.db_password
  port                   = 3306
  db_subnet_group_name   = aws_db_subnet_group.my_db1.name
  vpc_security_group_ids = [aws_security_group.rds_sg.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false

  tags = {
    Name = "my_db1"
  }
}

resource "aws_elastic_beanstalk_application" "app" {
  name        = var.beanstalk_app_name
  description = "Elastic Beanstalk application with CPU-based autoscaling and RDS connectivity"
}

resource "aws_elastic_beanstalk_environment" "env" {
  name                = var.beanstalk_env_name
  application         = aws_elastic_beanstalk_application.app.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.3.0 running Python 3.11"
  tier                = "WebServer"

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "LoadBalanced"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.eb_service_role.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_ec2_profile.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.eb_instance_sg.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = data.aws_vpc.default.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", data.aws_subnets.default.ids)
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = join(",", data.aws_subnets.default.ids)
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = "2"
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = "4"
  }

  setting {
    namespace = "aws:autoscaling:trigger"
    name      = "MeasureName"
    value     = "CPUUtilization"
  }

  setting {
    namespace = "aws:autoscaling:trigger"
    name      = "Statistic"
    value     = "Average"
  }

  setting {
    namespace = "aws:autoscaling:trigger"
    name      = "Unit"
    value     = "Percent"
  }

  setting {
    namespace = "aws:autoscaling:trigger"
    name      = "Period"
    value     = "5"
  }

  setting {
    namespace = "aws:autoscaling:trigger"
    name      = "BreachDuration"
    value     = "5"
  }

  setting {
    namespace = "aws:autoscaling:trigger"
    name      = "UpperThreshold"
    value     = "70"
  }

  setting {
    namespace = "aws:autoscaling:trigger"
    name      = "LowerThreshold"
    value     = "20"
  }

  setting {
    namespace = "aws:autoscaling:trigger"
    name      = "UpperBreachScaleIncrement"
    value     = "1"
  }

  setting {
    namespace = "aws:autoscaling:trigger"
    name      = "LowerBreachScaleIncrement"
    value     = "-1"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_NAME"
    value     = aws_db_instance.my_db1.db_name
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_HOST"
    value     = aws_db_instance.my_db1.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_PORT"
    value     = tostring(aws_db_instance.my_db1.port)
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_USERNAME"
    value     = var.db_username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_PASSWORD"
    value     = var.db_password
  }

  depends_on = [
    aws_db_instance.my_db1,
    aws_iam_role_policy_attachment.eb_web_tier,
    aws_iam_role_policy_attachment.eb_worker_tier,
    aws_iam_role_policy_attachment.eb_multicontainer_docker,
    aws_iam_role_policy_attachment.eb_service_role_enhanced_health,
    aws_iam_role_policy_attachment.eb_service_role_managed_updates
  ]

  tags = {
    Name = var.beanstalk_env_name
  }
}

output "elastic_beanstalk_environment_url" {
  description = "Elastic Beanstalk environment URL"
  value       = aws_elastic_beanstalk_environment.env.endpoint_url
}

output "rds_database_name" {
  description = "RDS database name"
  value       = aws_db_instance.my_db1.db_name
}

output "rds_endpoint" {
  description = "RDS database endpoint"
  value       = aws_db_instance.my_db1.endpoint
}

output "elastic_beanstalk_instance_profile" {
  description = "Elastic Beanstalk EC2 instance profile name"
  value       = aws_iam_instance_profile.eb_ec2_profile.name
}
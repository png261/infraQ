terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    random = {
      source  = "hashicorp/random"
      version = ">= 3.5"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "db_name" {
  description = "Name of the application database."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Username for the RDS database."
  type        = string
  default     = "dbadmin"
}

variable "environment_name" {
  description = "Elastic Beanstalk environment name."
  type        = string
  default     = "sample-eb-env"
}

variable "application_name" {
  description = "Elastic Beanstalk application name."
  type        = string
  default     = "sample-eb-app"
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

resource "random_password" "db_password" {
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_security_group" "elastic_beanstalk_ec2" {
  name        = "eb-ec2-sg"
  description = "Security group for Elastic Beanstalk EC2 instances"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTPS traffic"
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

  tags = {
    Name = "eb-ec2-sg"
  }
}

resource "aws_security_group" "rds" {
  name        = "eb-rds-sg"
  description = "Security group for RDS database accessed by Elastic Beanstalk"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Allow MySQL access from Elastic Beanstalk EC2 instances"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.elastic_beanstalk_ec2.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eb-rds-sg"
  }
}

resource "aws_db_subnet_group" "default" {
  name       = "eb-rds-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "eb-rds-subnet-group"
  }
}

resource "aws_db_instance" "default" {
  identifier             = "default"
  allocated_storage      = 20
  max_allocated_storage  = 100
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = var.db_name
  username               = var.db_username
  password               = random_password.db_password.result
  port                   = 3306
  db_subnet_group_name   = aws_db_subnet_group.default.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false
  storage_encrypted      = true

  tags = {
    Name = "default"
  }
}

resource "aws_iam_role" "eb_service_role" {
  name = "eb-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "elasticbeanstalk.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eb_service_role_enhanced_health" {
  role       = aws_iam_role.eb_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_iam_role_policy_attachment" "eb_service_role_managed_updates" {
  role       = aws_iam_role.eb_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy"
}

resource "aws_iam_role" "eb_ec2_role" {
  name = "eb-ec2-role"

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

resource "aws_iam_role_policy_attachment" "eb_ec2_web_tier" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_role_policy_attachment" "eb_ec2_worker_tier" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier"
}

resource "aws_iam_role_policy_attachment" "eb_ec2_multicontainer_docker" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
}

resource "aws_iam_instance_profile" "eb_ec2_profile" {
  name = "eb_ec2_profile"
  role = aws_iam_role.eb_ec2_role.name
}

resource "aws_elastic_beanstalk_application" "app" {
  name        = var.application_name
  description = "Elastic Beanstalk application linked to an RDS database"
}

resource "aws_elastic_beanstalk_environment" "env" {
  name                = var.environment_name
  application         = aws_elastic_beanstalk_application.app.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.3.0 running Docker"
  tier                = "WebServer"

  depends_on = [
    aws_db_instance.default,
    aws_iam_role_policy_attachment.eb_service_role_enhanced_health,
    aws_iam_role_policy_attachment.eb_service_role_managed_updates,
    aws_iam_role_policy_attachment.eb_ec2_web_tier,
    aws_iam_instance_profile.eb_ec2_profile
  ]

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.eb_service_role.name
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "SingleInstance"
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_ec2_profile.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.elastic_beanstalk_ec2.id
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
    name      = "AssociatePublicIpAddress"
    value     = "true"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_HOSTNAME"
    value     = aws_db_instance.default.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_PORT"
    value     = tostring(aws_db_instance.default.port)
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_DB_NAME"
    value     = aws_db_instance.default.db_name
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_USERNAME"
    value     = aws_db_instance.default.username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_PASSWORD"
    value     = random_password.db_password.result
  }

  tags = {
    Name = var.environment_name
  }
}

output "elastic_beanstalk_environment_name" {
  description = "Elastic Beanstalk environment name."
  value       = aws_elastic_beanstalk_environment.env.name
}

output "elastic_beanstalk_endpoint" {
  description = "Elastic Beanstalk environment endpoint URL."
  value       = aws_elastic_beanstalk_environment.env.endpoint_url
}

output "rds_instance_identifier" {
  description = "RDS instance identifier."
  value       = aws_db_instance.default.identifier
}

output "rds_endpoint" {
  description = "RDS database endpoint."
  value       = aws_db_instance.default.endpoint
}

output "eb_instance_profile_name" {
  description = "Elastic Beanstalk EC2 instance profile name."
  value       = aws_iam_instance_profile.eb_ec2_profile.name
}

output "rds_password" {
  description = "Generated RDS database password."
  value       = random_password.db_password.result
  sensitive   = true
}
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

provider "random" {}

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Route 53 hosted zone domain name."
  type        = string
  default     = "example.com"
}

variable "app_subdomain" {
  description = "Subdomain used for the application failover record."
  type        = string
  default     = "app"
}

variable "db_username" {
  description = "Master username for the shared RDS database."
  type        = string
  default     = "myappuser"
}

variable "db_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "eb_solution_stack_name" {
  description = "Elastic Beanstalk solution stack."
  type        = string
  default     = "64bit Amazon Linux 2023 v4.5.1 running Python 3.11"
}

data "aws_availability_zones" "available" {
  state = "available"
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
  length           = 24
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_security_group" "eb_instances" {
  name        = "myapp-eb-instances-sg"
  description = "Security group for Elastic Beanstalk EC2 instances"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from anywhere through load balancer"
    from_port   = 80
    to_port     = 80
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
    Name = "myapp-eb-instances-sg"
  }
}

resource "aws_security_group" "rds" {
  name        = "myapp-rds-sg"
  description = "Allow database access from Elastic Beanstalk environments"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "PostgreSQL from Elastic Beanstalk EC2 instances"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eb_instances.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "myapp-rds-sg"
  }
}

resource "aws_db_subnet_group" "myapp" {
  name       = "myapp-db-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "myapp-db-subnet-group"
  }
}

resource "aws_db_instance" "myapp_db" {
  identifier             = "myapp-db"
  db_name                = "myapp_db"
  engine                 = "postgres"
  engine_version         = "16.3"
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  storage_type           = "gp3"
  username               = var.db_username
  password               = random_password.db_password.result
  db_subnet_group_name   = aws_db_subnet_group.myapp.name
  vpc_security_group_ids = [aws_security_group.rds.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false
  multi_az               = false

  tags = {
    Name = "myapp_db"
  }
}

resource "aws_iam_role" "eb_service_role" {
  name = "myapp-eb-service-role"

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

resource "aws_iam_role_policy_attachment" "eb_service_enhanced_health" {
  role       = aws_iam_role.eb_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_iam_role_policy_attachment" "eb_service_managed_updates" {
  role       = aws_iam_role.eb_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy"
}

resource "aws_iam_role" "eb_ec2_role" {
  name = "myapp-eb-ec2-role"

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

resource "aws_iam_role_policy_attachment" "eb_ec2_multicontainer_docker" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
}

resource "aws_iam_role_policy_attachment" "eb_ec2_worker_tier" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier"
}

resource "aws_iam_instance_profile" "eb_ec2_profile" {
  name = "eb_ec2_profile"
  role = aws_iam_role.eb_ec2_role.name
}

resource "aws_elastic_beanstalk_application" "myapp" {
  name        = "myapp-blue-green"
  description = "Blue/green application connected to shared RDS database"
}

resource "aws_elastic_beanstalk_environment" "blue" {
  name                = "blue"
  application         = aws_elastic_beanstalk_application.myapp.name
  solution_stack_name = var.eb_solution_stack_name
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
    value     = aws_security_group.eb_instances.id
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = "1"
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = "2"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_HOST"
    value     = aws_db_instance.myapp_db.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_PORT"
    value     = "5432"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_NAME"
    value     = aws_db_instance.myapp_db.db_name
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_USERNAME"
    value     = var.db_username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_PASSWORD"
    value     = random_password.db_password.result
  }

  depends_on = [
    aws_iam_role_policy_attachment.eb_service_enhanced_health,
    aws_iam_role_policy_attachment.eb_service_managed_updates,
    aws_iam_role_policy_attachment.eb_ec2_web_tier,
    aws_db_instance.myapp_db
  ]

  tags = {
    Environment = "blue"
  }
}

resource "aws_elastic_beanstalk_environment" "green" {
  name                = "green"
  application         = aws_elastic_beanstalk_application.myapp.name
  solution_stack_name = var.eb_solution_stack_name
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
    value     = aws_security_group.eb_instances.id
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MinSize"
    value     = "1"
  }

  setting {
    namespace = "aws:autoscaling:asg"
    name      = "MaxSize"
    value     = "2"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_HOST"
    value     = aws_db_instance.myapp_db.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_PORT"
    value     = "5432"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_NAME"
    value     = aws_db_instance.myapp_db.db_name
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_USERNAME"
    value     = var.db_username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_PASSWORD"
    value     = random_password.db_password.result
  }

  depends_on = [
    aws_iam_role_policy_attachment.eb_service_enhanced_health,
    aws_iam_role_policy_attachment.eb_service_managed_updates,
    aws_iam_role_policy_attachment.eb_ec2_web_tier,
    aws_db_instance.myapp_db
  ]

  tags = {
    Environment = "green"
  }
}

resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Name = var.domain_name
  }
}

resource "aws_route53_health_check" "blue" {
  fqdn              = aws_elastic_beanstalk_environment.blue.cname
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name        = "blue-health-check"
    Environment = "blue"
  }
}

resource "aws_route53_health_check" "green" {
  fqdn              = aws_elastic_beanstalk_environment.green.cname
  port              = 80
  type              = "HTTP"
  resource_path     = "/"
  failure_threshold = 3
  request_interval  = 30

  tags = {
    Name        = "green-health-check"
    Environment = "green"
  }
}

resource "aws_route53_record" "blue_primary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "${var.app_subdomain}.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60

  set_identifier  = "blue-primary"
  health_check_id = aws_route53_health_check.blue.id
  records         = [aws_elastic_beanstalk_environment.blue.cname]

  failover_routing_policy {
    type = "PRIMARY"
  }
}

resource "aws_route53_record" "green_secondary" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "${var.app_subdomain}.${var.domain_name}"
  type    = "CNAME"
  ttl     = 60

  set_identifier  = "green-secondary"
  health_check_id = aws_route53_health_check.green.id
  records         = [aws_elastic_beanstalk_environment.green.cname]

  failover_routing_policy {
    type = "SECONDARY"
  }
}

output "route53_nameservers" {
  description = "Name servers for the created Route 53 hosted zone."
  value       = aws_route53_zone.main.name_servers
}

output "application_url" {
  description = "Failover DNS name for the blue/green application."
  value       = "http://${var.app_subdomain}.${var.domain_name}"
}

output "blue_environment_cname" {
  description = "Elastic Beanstalk CNAME for the blue environment."
  value       = aws_elastic_beanstalk_environment.blue.cname
}

output "green_environment_cname" {
  description = "Elastic Beanstalk CNAME for the green environment."
  value       = aws_elastic_beanstalk_environment.green.cname
}

output "rds_endpoint" {
  description = "Shared RDS endpoint used by both blue and green environments."
  value       = aws_db_instance.myapp_db.endpoint
}

output "database_name" {
  description = "Shared database name."
  value       = aws_db_instance.myapp_db.db_name
}
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

variable "db_username" {
  description = "Master username for the RDS database."
  type        = string
  default     = "adminuser"
}

variable "db_password" {
  description = "Master password for the RDS database."
  type        = string
  sensitive   = true
  default     = "ChangeMe12345!"
}

variable "eb_solution_stack_name" {
  description = "Elastic Beanstalk solution stack."
  type        = string
  default     = "64bit Amazon Linux 2023 v4.3.0 running Corretto 17"
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

resource "random_id" "suffix" {
  byte_length = 4
}

############################################
# Security Groups
############################################

resource "aws_security_group" "eb_instances" {
  name        = "eb-instances-sg-${random_id.suffix.hex}"
  description = "Security group for Elastic Beanstalk EC2 instances"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from anywhere"
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
    Name = "eb-instances-sg"
  }
}

resource "aws_security_group" "rds" {
  name        = "rds-my-db-sg-${random_id.suffix.hex}"
  description = "Security group for RDS database my_db"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Allow MySQL access from Elastic Beanstalk instances"
    from_port       = 3306
    to_port         = 3306
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
    Name = "rds-my-db-sg"
  }
}

############################################
# RDS Database and Snapshot
############################################

resource "aws_db_subnet_group" "my_db" {
  name       = "my-db-subnet-group-${random_id.suffix.hex}"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "my-db-subnet-group"
  }
}

resource "aws_db_instance" "my_db" {
  identifier             = "my-db-${random_id.suffix.hex}"
  db_name                = "my_db"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  allocated_storage      = 20
  storage_type           = "gp3"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.my_db.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible     = false
  multi_az                = false
  backup_retention_period = 7
  deletion_protection     = false
  skip_final_snapshot     = false
  final_snapshot_identifier = "my-db-final-snapshot-${random_id.suffix.hex}"

  tags = {
    Name = "my_db"
  }
}

resource "aws_db_snapshot" "pre_deployment" {
  db_instance_identifier = aws_db_instance.my_db.id
  db_snapshot_identifier = "my-db-pre-deployment-snapshot-${random_id.suffix.hex}"

  tags = {
    Name        = "my-db-pre-deployment-snapshot"
    Purpose     = "Pre-deployment snapshot before Elastic Beanstalk blue/green deployment"
    Database    = "my_db"
    Environment = "shared"
  }
}

############################################
# IAM Roles and Instance Profile
############################################

resource "aws_iam_role" "eb_ec2_role" {
  name = "ec2_eb_role1-${random_id.suffix.hex}"

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

  tags = {
    Name = "ec2_eb_role1"
  }
}

resource "aws_iam_role_policy_attachment" "eb_ec2_web_tier" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_role_policy_attachment" "eb_ec2_worker_tier" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier"
}

resource "aws_iam_role_policy_attachment" "eb_ec2_multicontainer" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
}

resource "aws_iam_instance_profile" "ec2_eb_profile1" {
  name = "ec2_eb_profile1"
  role = aws_iam_role.eb_ec2_role.name

  tags = {
    Name = "ec2_eb_profile1"
  }
}

resource "aws_iam_role" "eb_service_role" {
  name = "elastic-beanstalk-service-role-${random_id.suffix.hex}"

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

  tags = {
    Name = "elastic-beanstalk-service-role"
  }
}

resource "aws_iam_role_policy_attachment" "eb_service_enhanced_health" {
  role       = aws_iam_role.eb_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_iam_role_policy_attachment" "eb_service_managed_updates" {
  role       = aws_iam_role.eb_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy"
}

############################################
# Elastic Beanstalk Application
############################################

resource "aws_elastic_beanstalk_application" "app" {
  name        = "blue-green-rds-app-${random_id.suffix.hex}"
  description = "Elastic Beanstalk application with blue/green environments associated with RDS my_db"

  appversion_lifecycle {
    service_role          = aws_iam_role.eb_service_role.arn
    max_count             = 10
    delete_source_from_s3 = true
  }

  tags = {
    Name = "blue-green-rds-app"
  }
}

############################################
# Elastic Beanstalk Blue Environment
############################################

resource "aws_elastic_beanstalk_environment" "blue" {
  name                = "blue-env-${random_id.suffix.hex}"
  application         = aws_elastic_beanstalk_application.app.name
  solution_stack_name = var.eb_solution_stack_name
  cname_prefix        = "blue-${random_id.suffix.hex}"

  depends_on = [
    aws_db_snapshot.pre_deployment,
    aws_iam_instance_profile.ec2_eb_profile1,
    aws_iam_role_policy_attachment.eb_ec2_web_tier,
    aws_iam_role_policy_attachment.eb_service_enhanced_health
  ]

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
    value     = aws_iam_instance_profile.ec2_eb_profile1.name
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
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_HOSTNAME"
    value     = aws_db_instance.my_db.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_PORT"
    value     = tostring(aws_db_instance.my_db.port)
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_DB_NAME"
    value     = aws_db_instance.my_db.db_name
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_USERNAME"
    value     = var.db_username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_PASSWORD"
    value     = var.db_password
  }

  tags = {
    Name        = "blue-env"
    Deployment  = "blue"
    Database    = "my_db"
    Snapshot    = aws_db_snapshot.pre_deployment.id
  }
}

############################################
# Elastic Beanstalk Green Environment
############################################

resource "aws_elastic_beanstalk_environment" "green" {
  name                = "green-env-${random_id.suffix.hex}"
  application         = aws_elastic_beanstalk_application.app.name
  solution_stack_name = var.eb_solution_stack_name
  cname_prefix        = "green-${random_id.suffix.hex}"

  depends_on = [
    aws_db_snapshot.pre_deployment,
    aws_iam_instance_profile.ec2_eb_profile1,
    aws_iam_role_policy_attachment.eb_ec2_web_tier,
    aws_iam_role_policy_attachment.eb_service_enhanced_health
  ]

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
    value     = aws_iam_instance_profile.ec2_eb_profile1.name
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
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_HOSTNAME"
    value     = aws_db_instance.my_db.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_PORT"
    value     = tostring(aws_db_instance.my_db.port)
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_DB_NAME"
    value     = aws_db_instance.my_db.db_name
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_USERNAME"
    value     = var.db_username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_PASSWORD"
    value     = var.db_password
  }

  tags = {
    Name        = "green-env"
    Deployment  = "green"
    Database    = "my_db"
    Snapshot    = aws_db_snapshot.pre_deployment.id
  }
}

############################################
# Outputs
############################################

output "database_name" {
  description = "RDS database name."
  value       = aws_db_instance.my_db.db_name
}

output "database_endpoint" {
  description = "RDS database endpoint."
  value       = aws_db_instance.my_db.endpoint
}

output "pre_deployment_snapshot_id" {
  description = "RDS snapshot taken before Elastic Beanstalk environment deployment."
  value       = aws_db_snapshot.pre_deployment.id
}

output "instance_profile_name" {
  description = "Elastic Beanstalk EC2 instance profile name."
  value       = aws_iam_instance_profile.ec2_eb_profile1.name
}

output "blue_environment_url" {
  description = "Blue Elastic Beanstalk environment URL."
  value       = aws_elastic_beanstalk_environment.blue.endpoint_url
}

output "green_environment_url" {
  description = "Green Elastic Beanstalk environment URL."
  value       = aws_elastic_beanstalk_environment.green.endpoint_url
}
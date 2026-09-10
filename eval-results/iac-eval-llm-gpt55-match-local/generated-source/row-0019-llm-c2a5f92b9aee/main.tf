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
  description = "AWS region for all resources."
  type        = string
  default     = "us-east-1"
}

variable "rds_username" {
  description = "Master username for the shared RDS database."
  type        = string
  default     = "dbadmin"
}

variable "rds_password" {
  description = "Master password for the shared RDS database."
  type        = string
  sensitive   = true
  default     = "ChangeMe12345!"
}

variable "rds_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

variable "elastic_beanstalk_instance_type" {
  description = "EC2 instance type for Elastic Beanstalk environments."
  type        = string
  default     = "t3.micro"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_elastic_beanstalk_solution_stack" "python" {
  most_recent = true
  name_regex  = "^64bit Amazon Linux 2023 .* running Python 3\\.11$"
}

resource "aws_vpc" "eb_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "eb_vpc"
  }
}

resource "aws_internet_gateway" "eb_igw" {
  vpc_id = aws_vpc.eb_vpc.id

  tags = {
    Name = "eb_vpc_igw"
  }
}

resource "aws_subnet" "eb_subnet_public_1" {
  vpc_id                  = aws_vpc.eb_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "eb_subnet_public_1"
  }
}

resource "aws_subnet" "eb_subnet_public_2" {
  vpc_id                  = aws_vpc.eb_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "eb_subnet_public_2"
  }
}

resource "aws_route_table" "eb_public_route_table" {
  vpc_id = aws_vpc.eb_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eb_igw.id
  }

  tags = {
    Name = "eb_public_route_table"
  }
}

resource "aws_route_table_association" "eb_public_subnet_1_assoc" {
  subnet_id      = aws_subnet.eb_subnet_public_1.id
  route_table_id = aws_route_table.eb_public_route_table.id
}

resource "aws_route_table_association" "eb_public_subnet_2_assoc" {
  subnet_id      = aws_subnet.eb_subnet_public_2.id
  route_table_id = aws_route_table.eb_public_route_table.id
}

resource "aws_security_group" "eb_env_sg" {
  name        = "eb_env_sg"
  description = "Security group for Elastic Beanstalk environments and shared RDS access"
  vpc_id      = aws_vpc.eb_vpc.id

  ingress {
    description = "HTTP from the internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from the internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "PostgreSQL access within the Elastic Beanstalk security group"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eb_env_sg"
  }
}

resource "aws_db_subnet_group" "shared_rds_subnet_group" {
  name        = "shared-rds-subnet-group"
  description = "Subnet group for shared_rds"
  subnet_ids = [
    aws_subnet.eb_subnet_public_1.id,
    aws_subnet.eb_subnet_public_2.id
  ]

  tags = {
    Name = "shared_rds_subnet_group"
  }
}

resource "aws_db_instance" "shared_rds" {
  identifier             = "shared-rds"
  db_name                = "shared_rds"
  engine                 = "postgres"
  engine_version         = "16.3"
  instance_class         = var.rds_instance_class
  allocated_storage      = 20
  storage_type           = "gp3"
  username               = var.rds_username
  password               = var.rds_password
  db_subnet_group_name   = aws_db_subnet_group.shared_rds_subnet_group.name
  vpc_security_group_ids = [aws_security_group.eb_env_sg.id]
  publicly_accessible    = false
  multi_az               = false
  skip_final_snapshot    = true
  deletion_protection    = false

  tags = {
    Name = "shared_rds"
  }
}

resource "aws_iam_role" "elastic_beanstalk_service_role" {
  name = "elastic-beanstalk-service-role"

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

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_enhanced_health" {
  role       = aws_iam_role.elastic_beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_managed_updates" {
  role       = aws_iam_role.elastic_beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy"
}

resource "aws_iam_role" "elastic_beanstalk_ec2_role" {
  name = "elastic-beanstalk-ec2-role"

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
    Name = "elastic-beanstalk-ec2-role"
  }
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_web_tier" {
  role       = aws_iam_role.elastic_beanstalk_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_worker_tier" {
  role       = aws_iam_role.elastic_beanstalk_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier"
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_multicontainer_docker" {
  role       = aws_iam_role.elastic_beanstalk_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
}

resource "aws_iam_instance_profile" "elastic_beanstalk_instance_profile" {
  name = "elastic-beanstalk-ec2-instance-profile"
  role = aws_iam_role.elastic_beanstalk_ec2_role.name
}

resource "aws_elastic_beanstalk_application" "app_one" {
  name        = "eb-application-one"
  description = "First Elastic Beanstalk application connected to shared_rds"
}

resource "aws_elastic_beanstalk_application" "app_two" {
  name        = "eb-application-two"
  description = "Second Elastic Beanstalk application connected to shared_rds"
}

resource "aws_elastic_beanstalk_environment" "environment_one" {
  name                = "eb-environment-one"
  application         = aws_elastic_beanstalk_application.app_one.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.python.name

  tier = "WebServer"

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "LoadBalanced"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.elastic_beanstalk_service_role.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.elastic_beanstalk_instance_profile.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = var.elastic_beanstalk_instance_type
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.eb_env_sg.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = aws_vpc.eb_vpc.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", [
      aws_subnet.eb_subnet_public_1.id,
      aws_subnet.eb_subnet_public_2.id
    ])
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = join(",", [
      aws_subnet.eb_subnet_public_1.id,
      aws_subnet.eb_subnet_public_2.id
    ])
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBScheme"
    value     = "public"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_DB_NAME"
    value     = aws_db_instance.shared_rds.db_name
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_HOSTNAME"
    value     = aws_db_instance.shared_rds.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_PORT"
    value     = tostring(aws_db_instance.shared_rds.port)
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_USERNAME"
    value     = var.rds_username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_PASSWORD"
    value     = var.rds_password
  }

  depends_on = [
    aws_db_instance.shared_rds,
    aws_iam_role_policy_attachment.elastic_beanstalk_enhanced_health,
    aws_iam_role_policy_attachment.elastic_beanstalk_managed_updates,
    aws_iam_role_policy_attachment.elastic_beanstalk_web_tier
  ]

  tags = {
    Name = "eb-environment-one"
  }
}

resource "aws_elastic_beanstalk_environment" "environment_two" {
  name                = "eb-environment-two"
  application         = aws_elastic_beanstalk_application.app_two.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.python.name

  tier = "WebServer"

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "LoadBalanced"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.elastic_beanstalk_service_role.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.elastic_beanstalk_instance_profile.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = var.elastic_beanstalk_instance_type
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.eb_env_sg.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = aws_vpc.eb_vpc.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", [
      aws_subnet.eb_subnet_public_1.id,
      aws_subnet.eb_subnet_public_2.id
    ])
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = join(",", [
      aws_subnet.eb_subnet_public_1.id,
      aws_subnet.eb_subnet_public_2.id
    ])
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBScheme"
    value     = "public"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_DB_NAME"
    value     = aws_db_instance.shared_rds.db_name
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_HOSTNAME"
    value     = aws_db_instance.shared_rds.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_PORT"
    value     = tostring(aws_db_instance.shared_rds.port)
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_USERNAME"
    value     = var.rds_username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_PASSWORD"
    value     = var.rds_password
  }

  depends_on = [
    aws_db_instance.shared_rds,
    aws_iam_role_policy_attachment.elastic_beanstalk_enhanced_health,
    aws_iam_role_policy_attachment.elastic_beanstalk_managed_updates,
    aws_iam_role_policy_attachment.elastic_beanstalk_web_tier
  ]

  tags = {
    Name = "eb-environment-two"
  }
}

output "vpc_id" {
  description = "ID of the Elastic Beanstalk VPC."
  value       = aws_vpc.eb_vpc.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value = [
    aws_subnet.eb_subnet_public_1.id,
    aws_subnet.eb_subnet_public_2.id
  ]
}

output "security_group_id" {
  description = "ID of the Elastic Beanstalk security group."
  value       = aws_security_group.eb_env_sg.id
}

output "shared_rds_endpoint" {
  description = "Endpoint of the shared RDS database."
  value       = aws_db_instance.shared_rds.endpoint
}

output "elastic_beanstalk_environment_one_cname" {
  description = "CNAME for the first Elastic Beanstalk environment."
  value       = aws_elastic_beanstalk_environment.environment_one.cname
}

output "elastic_beanstalk_environment_two_cname" {
  description = "CNAME for the second Elastic Beanstalk environment."
  value       = aws_elastic_beanstalk_environment.environment_two.cname
}
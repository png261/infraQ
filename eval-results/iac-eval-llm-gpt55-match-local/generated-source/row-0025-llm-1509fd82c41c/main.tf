terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

############################################
# Variables
############################################

variable "domain_name" {
  description = "Domain name to manage in Route 53."
  type        = string
  default     = "example.com"
}

variable "db_username" {
  description = "Master username for the RDS databases."
  type        = string
  default     = "dbadmin"
}

variable "db_password" {
  description = "Master password for the RDS databases."
  type        = string
  sensitive   = true
  default     = "ChangeMe12345!"
}

variable "eb_instance_type" {
  description = "EC2 instance type for Elastic Beanstalk environments."
  type        = string
  default     = "t3.micro"
}

variable "rds_instance_class" {
  description = "RDS instance class."
  type        = string
  default     = "db.t3.micro"
}

############################################
# Providers
############################################

provider "aws" {
  region = "us-east-1"
}

provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"
}

############################################
# IAM for Elastic Beanstalk
############################################

resource "aws_iam_role" "eb_ec2_role" {
  name = "eb_ec2_role3"

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

resource "aws_iam_role_policy_attachment" "eb_worker_tier" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier"
}

resource "aws_iam_role_policy_attachment" "eb_multicontainer_docker" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
}

resource "aws_iam_instance_profile" "eb_ec2_profile3" {
  name = "eb_ec2_profile3"
  role = aws_iam_role.eb_ec2_role.name
}

resource "aws_iam_role" "eb_service_role" {
  name = "eb_service_role3"

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

############################################
# Networking Data - us-east-1
############################################

data "aws_vpc" "default_us_east" {
  default = true
}

data "aws_subnets" "default_us_east" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default_us_east.id]
  }
}

############################################
# Networking Data - eu-west-1
############################################

data "aws_vpc" "default_eu_west" {
  provider = aws.eu_west_1
  default  = true
}

data "aws_subnets" "default_eu_west" {
  provider = aws.eu_west_1

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default_eu_west.id]
  }
}

############################################
# Elastic Beanstalk Platform Data
############################################

data "aws_elastic_beanstalk_solution_stack" "python_us_east" {
  most_recent = true
  name_regex  = "^64bit Amazon Linux 2023 v.* running Python 3.11$"
}

data "aws_elastic_beanstalk_solution_stack" "python_eu_west" {
  provider    = aws.eu_west_1
  most_recent = true
  name_regex  = "^64bit Amazon Linux 2023 v.* running Python 3.11$"
}

data "aws_elastic_beanstalk_hosted_zone" "us_east" {}

data "aws_elastic_beanstalk_hosted_zone" "eu_west" {
  provider = aws.eu_west_1
}

############################################
# Security Groups - us-east-1
############################################

resource "aws_security_group" "eb_us_east" {
  name        = "eb-sg-us-east-1"
  description = "Security group for Elastic Beanstalk in us-east-1"
  vpc_id      = data.aws_vpc.default_us_east.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from internet"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name = "eb-sg-us-east-1"
  }
}

resource "aws_security_group" "rds_us_east" {
  name        = "rds-sg-us-east-1"
  description = "Security group for RDS in us-east-1"
  vpc_id      = data.aws_vpc.default_us_east.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eb_us_east.id]
    description     = "PostgreSQL from Elastic Beanstalk"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name = "rds-sg-us-east-1"
  }
}

############################################
# Security Groups - eu-west-1
############################################

resource "aws_security_group" "eb_eu_west" {
  provider    = aws.eu_west_1
  name        = "eb-sg-eu-west-1"
  description = "Security group for Elastic Beanstalk in eu-west-1"
  vpc_id      = data.aws_vpc.default_eu_west.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP from internet"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS from internet"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name = "eb-sg-eu-west-1"
  }
}

resource "aws_security_group" "rds_eu_west" {
  provider    = aws.eu_west_1
  name        = "rds-sg-eu-west-1"
  description = "Security group for RDS in eu-west-1"
  vpc_id      = data.aws_vpc.default_eu_west.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eb_eu_west.id]
    description     = "PostgreSQL from Elastic Beanstalk"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name = "rds-sg-eu-west-1"
  }
}

############################################
# RDS - us-east-1
############################################

resource "aws_db_subnet_group" "main_db_us_east" {
  name       = "main-db-us-east-subnet-group"
  subnet_ids = data.aws_subnets.default_us_east.ids

  tags = {
    Name = "main_db_us_east"
  }
}

resource "aws_db_instance" "main_db_us_east" {
  identifier             = "main-db-us-east"
  db_name                = "main_db_us_east"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = var.rds_instance_class
  allocated_storage      = 20
  storage_type           = "gp3"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.main_db_us_east.name
  vpc_security_group_ids = [aws_security_group.rds_us_east.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false
  multi_az               = false

  tags = {
    Name = "main_db_us_east"
  }
}

############################################
# RDS - eu-west-1
############################################

resource "aws_db_subnet_group" "main_db_eu_west" {
  provider   = aws.eu_west_1
  name       = "main-db-eu-west-subnet-group"
  subnet_ids = data.aws_subnets.default_eu_west.ids

  tags = {
    Name = "main_db_eu_west"
  }
}

resource "aws_db_instance" "main_db_eu_west" {
  provider               = aws.eu_west_1
  identifier             = "main-db-eu-west"
  db_name                = "main_db_eu_west"
  engine                 = "postgres"
  engine_version         = "16"
  instance_class         = var.rds_instance_class
  allocated_storage      = 20
  storage_type           = "gp3"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.main_db_eu_west.name
  vpc_security_group_ids = [aws_security_group.rds_eu_west.id]
  publicly_accessible    = false
  skip_final_snapshot    = true
  deletion_protection    = false
  multi_az               = false

  tags = {
    Name = "main_db_eu_west"
  }
}

############################################
# Elastic Beanstalk - us-east-1
############################################

resource "aws_elastic_beanstalk_application" "myapp_us_east" {
  name        = "myapp_us_east"
  description = "Elastic Beanstalk application for us-east-1"
}

resource "aws_elastic_beanstalk_environment" "myenv_us_east" {
  name                = "myenv_us_east"
  application         = aws_elastic_beanstalk_application.myapp_us_east.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.python_us_east.name
  tier                = "WebServer"

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "LoadBalanced"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.eb_service_role.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_ec2_profile3.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = var.eb_instance_type
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.eb_us_east.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = data.aws_vpc.default_us_east.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", data.aws_subnets.default_us_east.ids)
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = join(",", data.aws_subnets.default_us_east.ids)
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "AssociatePublicIpAddress"
    value     = "true"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_HOSTNAME"
    value     = aws_db_instance.main_db_us_east.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_PORT"
    value     = "5432"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_DB_NAME"
    value     = aws_db_instance.main_db_us_east.db_name
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

  depends_on = [
    aws_db_instance.main_db_us_east,
    aws_iam_role_policy_attachment.eb_web_tier,
    aws_iam_role_policy_attachment.eb_service_enhanced_health,
    aws_iam_role_policy_attachment.eb_service_managed_updates
  ]
}

############################################
# Elastic Beanstalk - eu-west-1
############################################

resource "aws_elastic_beanstalk_application" "myapp_eu_west" {
  provider    = aws.eu_west_1
  name        = "myapp_eu_west"
  description = "Elastic Beanstalk application for eu-west-1"
}

resource "aws_elastic_beanstalk_environment" "myenv_eu_west" {
  provider            = aws.eu_west_1
  name                = "myenv_eu_west"
  application         = aws_elastic_beanstalk_application.myapp_eu_west.name
  solution_stack_name = data.aws_elastic_beanstalk_solution_stack.python_eu_west.name
  tier                = "WebServer"

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "EnvironmentType"
    value     = "LoadBalanced"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "LoadBalancerType"
    value     = "application"
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.eb_service_role.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_ec2_profile3.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = var.eb_instance_type
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.eb_eu_west.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = data.aws_vpc.default_eu_west.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", data.aws_subnets.default_eu_west.ids)
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = join(",", data.aws_subnets.default_eu_west.ids)
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "AssociatePublicIpAddress"
    value     = "true"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_HOSTNAME"
    value     = aws_db_instance.main_db_eu_west.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_PORT"
    value     = "5432"
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_DB_NAME"
    value     = aws_db_instance.main_db_eu_west.db_name
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

  depends_on = [
    aws_db_instance.main_db_eu_west,
    aws_iam_role_policy_attachment.eb_web_tier,
    aws_iam_role_policy_attachment.eb_service_enhanced_health,
    aws_iam_role_policy_attachment.eb_service_managed_updates
  ]
}

############################################
# Route 53
############################################

resource "aws_route53_zone" "main" {
  name = var.domain_name

  tags = {
    Name = var.domain_name
  }
}

resource "aws_route53_record" "us_east_1_alias" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "us-east-1.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_elastic_beanstalk_environment.myenv_us_east.cname
    zone_id                = data.aws_elastic_beanstalk_hosted_zone.us_east.id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "eu_west_1_alias" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "eu-west-1.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_elastic_beanstalk_environment.myenv_eu_west.cname
    zone_id                = data.aws_elastic_beanstalk_hosted_zone.eu_west.id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "global_weighted_us_east" {
  zone_id        = aws_route53_zone.main.zone_id
  name           = var.domain_name
  type           = "A"
  set_identifier = "us-east-1"

  weighted_routing_policy {
    weight = 50
  }

  alias {
    name                   = aws_elastic_beanstalk_environment.myenv_us_east.cname
    zone_id                = data.aws_elastic_beanstalk_hosted_zone.us_east.id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "global_weighted_eu_west" {
  zone_id        = aws_route53_zone.main.zone_id
  name           = var.domain_name
  type           = "A"
  set_identifier = "eu-west-1"

  weighted_routing_policy {
    weight = 50
  }

  alias {
    name                   = aws_elastic_beanstalk_environment.myenv_eu_west.cname
    zone_id                = data.aws_elastic_beanstalk_hosted_zone.eu_west.id
    evaluate_target_health = true
  }
}

############################################
# Outputs
############################################

output "route53_zone_id" {
  description = "Route 53 hosted zone ID."
  value       = aws_route53_zone.main.zone_id
}

output "route53_name_servers" {
  description = "Name servers for the Route 53 hosted zone."
  value       = aws_route53_zone.main.name_servers
}

output "us_east_beanstalk_cname" {
  description = "Elastic Beanstalk CNAME for us-east-1."
  value       = aws_elastic_beanstalk_environment.myenv_us_east.cname
}

output "eu_west_beanstalk_cname" {
  description = "Elastic Beanstalk CNAME for eu-west-1."
  value       = aws_elastic_beanstalk_environment.myenv_eu_west.cname
}

output "us_east_alias_record" {
  description = "Regional alias record for us-east-1."
  value       = aws_route53_record.us_east_1_alias.fqdn
}

output "eu_west_alias_record" {
  description = "Regional alias record for eu-west-1."
  value       = aws_route53_record.eu_west_1_alias.fqdn
}

output "global_application_record" {
  description = "Weighted global application DNS record."
  value       = var.domain_name
}

output "main_db_us_east_endpoint" {
  description = "RDS endpoint for us-east-1."
  value       = aws_db_instance.main_db_us_east.endpoint
  sensitive   = true
}

output "main_db_eu_west_endpoint" {
  description = "RDS endpoint for eu-west-1."
  value       = aws_db_instance.main_db_eu_west.endpoint
  sensitive   = true
}
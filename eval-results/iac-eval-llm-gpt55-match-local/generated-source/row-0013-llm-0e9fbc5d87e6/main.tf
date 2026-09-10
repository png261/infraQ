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
  description = "The domain name for the Route53 hosted zone."
  type        = string
  default     = "example.com"
}

variable "application_name" {
  description = "Elastic Beanstalk application name."
  type        = string
  default     = "geo-routing-eb-app"
}

variable "environment_instance_type" {
  description = "EC2 instance type for Elastic Beanstalk environments."
  type        = string
  default     = "t3.micro"
}

variable "solution_stack_name" {
  description = "Elastic Beanstalk solution stack."
  type        = string
  default     = "64bit Amazon Linux 2023 v4.3.1 running Python 3.11"
}

############################################
# Providers
############################################

provider "aws" {
  region = "us-west-2"
}

provider "aws" {
  alias  = "us_west"
  region = "us-west-2"
}

provider "aws" {
  alias  = "eu_central"
  region = "eu-central-1"
}

############################################
# Locals
############################################

locals {
  route53_record_name = "app.${var.domain_name}"

  elastic_beanstalk_hosted_zone_ids = {
    us-west-2    = "Z1H1FL5HABSF5"
    eu-central-1 = "Z1FRNW7UH4DEZJ"
  }
}

############################################
# IAM Roles for Elastic Beanstalk
############################################

resource "aws_iam_role" "elastic_beanstalk_service_role" {
  name = "elastic-beanstalk-service-role-geo-routing"

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

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_enhanced_health" {
  role       = aws_iam_role.elastic_beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_managed_updates" {
  role       = aws_iam_role.elastic_beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy"
}

resource "aws_iam_role" "elastic_beanstalk_ec2_role" {
  name = "elastic-beanstalk-ec2-role-geo-routing"

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

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_web_tier" {
  role       = aws_iam_role.elastic_beanstalk_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_multicontainer_docker" {
  role       = aws_iam_role.elastic_beanstalk_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkMulticontainerDocker"
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_worker_tier" {
  role       = aws_iam_role.elastic_beanstalk_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWorkerTier"
}

resource "aws_iam_instance_profile" "elastic_beanstalk_instance_profile" {
  name = "elastic-beanstalk-instance-profile-geo-routing"
  role = aws_iam_role.elastic_beanstalk_ec2_role.name
}

############################################
# Elastic Beanstalk Applications
############################################

resource "aws_elastic_beanstalk_application" "us_west" {
  provider = aws.us_west

  name        = "${var.application_name}-us-west"
  description = "Elastic Beanstalk application for the us_west environment"
}

resource "aws_elastic_beanstalk_application" "eu_central" {
  provider = aws.eu_central

  name        = "${var.application_name}-eu-central"
  description = "Elastic Beanstalk application for the eu_central environment"
}

############################################
# US West Networking
############################################

resource "aws_vpc" "us_west" {
  provider = aws.us_west

  cidr_block           = "10.10.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "us-west-eb-vpc"
  }
}

resource "aws_internet_gateway" "us_west" {
  provider = aws.us_west

  vpc_id = aws_vpc.us_west.id

  tags = {
    Name = "us-west-eb-igw"
  }
}

resource "aws_subnet" "us_west_a" {
  provider = aws.us_west

  vpc_id                  = aws_vpc.us_west.id
  cidr_block              = "10.10.1.0/24"
  availability_zone       = "us-west-2a"
  map_public_ip_on_launch = true

  tags = {
    Name = "us-west-eb-public-a"
  }
}

resource "aws_subnet" "us_west_b" {
  provider = aws.us_west

  vpc_id                  = aws_vpc.us_west.id
  cidr_block              = "10.10.2.0/24"
  availability_zone       = "us-west-2b"
  map_public_ip_on_launch = true

  tags = {
    Name = "us-west-eb-public-b"
  }
}

resource "aws_route_table" "us_west" {
  provider = aws.us_west

  vpc_id = aws_vpc.us_west.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.us_west.id
  }

  tags = {
    Name = "us-west-eb-public-rt"
  }
}

resource "aws_route_table_association" "us_west_a" {
  provider = aws.us_west

  subnet_id      = aws_subnet.us_west_a.id
  route_table_id = aws_route_table.us_west.id
}

resource "aws_route_table_association" "us_west_b" {
  provider = aws.us_west

  subnet_id      = aws_subnet.us_west_b.id
  route_table_id = aws_route_table.us_west.id
}

resource "aws_security_group" "us_west_beanstalk" {
  provider = aws.us_west

  name        = "us-west-eb-sg"
  description = "Security group for us_west Elastic Beanstalk environment"
  vpc_id      = aws_vpc.us_west.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "us-west-eb-sg"
  }
}

############################################
# EU Central Networking
############################################

resource "aws_vpc" "eu_central" {
  provider = aws.eu_central

  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "eu-central-eb-vpc"
  }
}

resource "aws_internet_gateway" "eu_central" {
  provider = aws.eu_central

  vpc_id = aws_vpc.eu_central.id

  tags = {
    Name = "eu-central-eb-igw"
  }
}

resource "aws_subnet" "eu_central_a" {
  provider = aws.eu_central

  vpc_id                  = aws_vpc.eu_central.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = "eu-central-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "eu-central-eb-public-a"
  }
}

resource "aws_subnet" "eu_central_b" {
  provider = aws.eu_central

  vpc_id                  = aws_vpc.eu_central.id
  cidr_block              = "10.20.2.0/24"
  availability_zone       = "eu-central-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "eu-central-eb-public-b"
  }
}

resource "aws_route_table" "eu_central" {
  provider = aws.eu_central

  vpc_id = aws_vpc.eu_central.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eu_central.id
  }

  tags = {
    Name = "eu-central-eb-public-rt"
  }
}

resource "aws_route_table_association" "eu_central_a" {
  provider = aws.eu_central

  subnet_id      = aws_subnet.eu_central_a.id
  route_table_id = aws_route_table.eu_central.id
}

resource "aws_route_table_association" "eu_central_b" {
  provider = aws.eu_central

  subnet_id      = aws_subnet.eu_central_b.id
  route_table_id = aws_route_table.eu_central.id
}

resource "aws_security_group" "eu_central_beanstalk" {
  provider = aws.eu_central

  name        = "eu-central-eb-sg"
  description = "Security group for eu_central Elastic Beanstalk environment"
  vpc_id      = aws_vpc.eu_central.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eu-central-eb-sg"
  }
}

############################################
# Elastic Beanstalk Environments
############################################

resource "aws_elastic_beanstalk_environment" "us_west" {
  provider = aws.us_west

  name                = "us_west"
  application         = aws_elastic_beanstalk_application.us_west.name
  solution_stack_name = var.solution_stack_name

  tier = "WebServer"

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
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.elastic_beanstalk_instance_profile.name
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.elastic_beanstalk_service_role.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = var.environment_instance_type
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
    value     = aws_vpc.us_west.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = "${aws_subnet.us_west_a.id},${aws_subnet.us_west_b.id}"
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = "${aws_subnet.us_west_a.id},${aws_subnet.us_west_b.id}"
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBScheme"
    value     = "public"
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "AssociatePublicIpAddress"
    value     = "true"
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.us_west_beanstalk.id
  }

  depends_on = [
    aws_iam_role_policy_attachment.elastic_beanstalk_enhanced_health,
    aws_iam_role_policy_attachment.elastic_beanstalk_managed_updates,
    aws_iam_role_policy_attachment.elastic_beanstalk_web_tier,
    aws_route_table_association.us_west_a,
    aws_route_table_association.us_west_b
  ]
}

resource "aws_elastic_beanstalk_environment" "eu_central" {
  provider = aws.eu_central

  name                = "eu_central"
  application         = aws_elastic_beanstalk_application.eu_central.name
  solution_stack_name = var.solution_stack_name

  tier = "WebServer"

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
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.elastic_beanstalk_instance_profile.name
  }

  setting {
    namespace = "aws:elasticbeanstalk:environment"
    name      = "ServiceRole"
    value     = aws_iam_role.elastic_beanstalk_service_role.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = var.environment_instance_type
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
    value     = aws_vpc.eu_central.id
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = "${aws_subnet.eu_central_a.id},${aws_subnet.eu_central_b.id}"
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBSubnets"
    value     = "${aws_subnet.eu_central_a.id},${aws_subnet.eu_central_b.id}"
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "ELBScheme"
    value     = "public"
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "AssociatePublicIpAddress"
    value     = "true"
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.eu_central_beanstalk.id
  }

  depends_on = [
    aws_iam_role_policy_attachment.elastic_beanstalk_enhanced_health,
    aws_iam_role_policy_attachment.elastic_beanstalk_managed_updates,
    aws_iam_role_policy_attachment.elastic_beanstalk_web_tier,
    aws_route_table_association.eu_central_a,
    aws_route_table_association.eu_central_b
  ]
}

############################################
# Route53 Hosted Zone and Geolocation Records
############################################

resource "aws_route53_zone" "main" {
  name = var.domain_name
}

resource "aws_route53_record" "eu_central_geolocation" {
  zone_id = aws_route53_zone.main.zone_id
  name    = local.route53_record_name
  type    = "A"

  set_identifier = "eu-central-geolocation"

  geolocation_routing_policy {
    continent = "EU"
  }

  alias {
    name                   = aws_elastic_beanstalk_environment.eu_central.cname
    zone_id                = local.elastic_beanstalk_hosted_zone_ids["eu-central-1"]
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "us_west_geolocation" {
  zone_id = aws_route53_zone.main.zone_id
  name    = local.route53_record_name
  type    = "A"

  set_identifier = "us-west-geolocation"

  geolocation_routing_policy {
    country = "US"
  }

  alias {
    name                   = aws_elastic_beanstalk_environment.us_west.cname
    zone_id                = local.elastic_beanstalk_hosted_zone_ids["us-west-2"]
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "default_geolocation" {
  zone_id = aws_route53_zone.main.zone_id
  name    = local.route53_record_name
  type    = "A"

  set_identifier = "default-to-us-west"

  geolocation_routing_policy {
    country = "*"
  }

  alias {
    name                   = aws_elastic_beanstalk_environment.us_west.cname
    zone_id                = local.elastic_beanstalk_hosted_zone_ids["us-west-2"]
    evaluate_target_health = true
  }
}

############################################
# Outputs
############################################

output "route53_zone_id" {
  description = "Route53 hosted zone ID."
  value       = aws_route53_zone.main.zone_id
}

output "route53_name_servers" {
  description = "Name servers for the Route53 hosted zone. Configure these at your domain registrar."
  value       = aws_route53_zone.main.name_servers
}

output "application_url" {
  description = "Geolocation-routed application URL."
  value       = "http://${local.route53_record_name}"
}

output "us_west_environment_cname" {
  description = "Elastic Beanstalk CNAME for us_west."
  value       = aws_elastic_beanstalk_environment.us_west.cname
}

output "eu_central_environment_cname" {
  description = "Elastic Beanstalk CNAME for eu_central."
  value       = aws_elastic_beanstalk_environment.eu_central.cname
}
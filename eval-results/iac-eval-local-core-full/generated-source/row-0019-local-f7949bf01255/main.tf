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

resource "aws_iam_role_policy_attachment" "eb_web_tier" {
  role       = aws_iam_role.eb_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkWebTier"
}

resource "aws_iam_instance_profile" "eb_instance_profile" {
  name = "eb-instance-profile"
  role = aws_iam_role.eb_ec2_role.name
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
    Name = "eb_igw"
  }
}

resource "aws_subnet" "eb_subnet_public_1" {
  vpc_id                  = aws_vpc.eb_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "eb_subnet_public_1"
  }
}

resource "aws_subnet" "eb_subnet_public_2" {
  vpc_id                  = aws_vpc.eb_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "eb_subnet_public_2"
  }
}

resource "aws_security_group" "eb_env_sg" {
  name        = "eb_env_sg"
  description = "Security group for Elastic Beanstalk environments and shared RDS"
  vpc_id      = aws_vpc.eb_vpc.id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "MySQL from resources in this security group"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eb_env_sg"
  }
}

resource "aws_db_subnet_group" "shared_rds" {
  name       = "shared-rds-subnet-group"
  subnet_ids = [aws_subnet.eb_subnet_public_1.id, aws_subnet.eb_subnet_public_2.id]

  tags = {
    Name = "shared_rds"
  }
}

resource "aws_route_table" "eb_public_rt" {
  vpc_id = aws_vpc.eb_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.eb_igw.id
  }

  tags = {
    Name = "eb_public_rt"
  }
}

resource "aws_route_table_association" "eb_public_1" {
  subnet_id      = aws_subnet.eb_subnet_public_1.id
  route_table_id = aws_route_table.eb_public_rt.id
}

resource "aws_route_table_association" "eb_public_2" {
  subnet_id      = aws_subnet.eb_subnet_public_2.id
  route_table_id = aws_route_table.eb_public_rt.id
}

resource "aws_db_instance" "shared_rds" {
  identifier              = "shared-rds"
  allocated_storage       = 20
  instance_class          = "db.t3.micro"
  engine                  = "mysql"
  engine_version          = "8.0"
  username                = "adminuser"
  password                = var.db_password
  backup_retention_period = 7
  skip_final_snapshot     = true
  db_subnet_group_name    = aws_db_subnet_group.shared_rds.name
  vpc_security_group_ids  = [aws_security_group.eb_env_sg.id]
}

resource "aws_elastic_beanstalk_application" "app" {
  name = "eb-shared-rds-app"
}

resource "aws_elastic_beanstalk_environment" "environment_1" {
  name                = "eb-env-1"
  application         = aws_elastic_beanstalk_application.app.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.3.0 running Corretto 17"

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_instance_profile.name
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", [aws_subnet.eb_subnet_public_1.id, aws_subnet.eb_subnet_public_2.id])
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = aws_vpc.eb_vpc.id
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.eb_env_sg.id
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_HOSTNAME"
    value     = aws_db_instance.shared_rds.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_USERNAME"
    value     = aws_db_instance.shared_rds.username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_PASSWORD"
    value     = aws_db_instance.shared_rds.password
  }
}

resource "aws_elastic_beanstalk_environment" "environment_2" {
  name                = "eb-env-2"
  application         = aws_elastic_beanstalk_application.app.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.3.0 running Corretto 17"

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "IamInstanceProfile"
    value     = aws_iam_instance_profile.eb_instance_profile.name
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "Subnets"
    value     = join(",", [aws_subnet.eb_subnet_public_1.id, aws_subnet.eb_subnet_public_2.id])
  }

  setting {
    namespace = "aws:ec2:vpc"
    name      = "VPCId"
    value     = aws_vpc.eb_vpc.id
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.eb_env_sg.id
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_HOSTNAME"
    value     = aws_db_instance.shared_rds.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_USERNAME"
    value     = aws_db_instance.shared_rds.username
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "RDS_PASSWORD"
    value     = aws_db_instance.shared_rds.password
  }
}

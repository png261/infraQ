terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }

    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
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
  default     = "dbadmin"
}

variable "db_password" {
  description = "Master password for the RDS database."
  type        = string
  sensitive   = true
  default     = "ChangeMe12345!"
}

variable "eb_instance_type" {
  description = "EC2 instance type for Elastic Beanstalk environments."
  type        = string
  default     = "t3.micro"
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "elastic_beanstalk_instances" {
  name        = "eb-blue-green-instance-sg"
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

  tags = {
    Name = "eb-blue-green-instance-sg"
  }
}

resource "aws_security_group" "rds" {
  name        = "eb-blue-green-rds-sg"
  description = "Security group for RDS database used by Elastic Beanstalk"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description     = "Allow PostgreSQL from Elastic Beanstalk instances"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.elastic_beanstalk_instances.id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "eb-blue-green-rds-sg"
  }
}

resource "aws_db_subnet_group" "rds" {
  name       = "my-db-subnet-group"
  subnet_ids = data.aws_subnets.default.ids

  tags = {
    Name = "my-db-subnet-group"
  }
}

resource "aws_db_instance" "my_db" {
  identifier = "my-db"

  engine         = "postgres"
  engine_version = "16.3"
  instance_class = "db.t3.micro"

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"

  db_name  = "my_db"
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.rds.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  publicly_accessible = false
  multi_az            = false

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:30-sun:05:30"

  skip_final_snapshot       = false
  final_snapshot_identifier = "my-db-final-snapshot"

  deletion_protection = false

  tags = {
    Name = "my_db"
  }
}

resource "aws_db_snapshot" "pre_deployment" {
  db_instance_identifier = aws_db_instance.my_db.identifier
  db_snapshot_identifier = "my-db-pre-deployment-snapshot"

  tags = {
    Name        = "my-db-pre-deployment-snapshot"
    Purpose     = "Pre-deployment database snapshot"
    Environment = "blue-green"
  }
}

resource "aws_iam_role" "elastic_beanstalk_service_role" {
  name = "eb-blue-green-service-role"

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
    Name = "eb-blue-green-service-role"
  }
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_service_role_enhanced_health" {
  role       = aws_iam_role.elastic_beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSElasticBeanstalkEnhancedHealth"
}

resource "aws_iam_role_policy_attachment" "elastic_beanstalk_service_role_managed_updates" {
  role       = aws_iam_role.elastic_beanstalk_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AWSElasticBeanstalkManagedUpdatesCustomerRolePolicy"
}

resource "aws_iam_role" "elastic_beanstalk_ec2_role" {
  name = "eb-blue-green-ec2-role"

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
    Name = "eb-blue-green-ec2-role"
  }
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

resource "aws_iam_instance_profile" "ec2_eb_profile1" {
  name = "ec2_eb_profile1"
  role = aws_iam_role.elastic_beanstalk_ec2_role.name
}

resource "aws_s3_bucket" "elastic_beanstalk_source" {
  bucket = "eb-blue-green-source-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  tags = {
    Name = "eb-blue-green-source"
  }
}

resource "aws_s3_bucket_ownership_controls" "elastic_beanstalk_source" {
  bucket = aws_s3_bucket.elastic_beanstalk_source.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "elastic_beanstalk_source" {
  bucket = aws_s3_bucket.elastic_beanstalk_source.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "local_file" "dockerfile" {
  filename = "${path.module}/eb-app/Dockerfile"

  content = <<EOF
FROM nginx:alpine
RUN echo '<html><body><h1>Elastic Beanstalk Blue/Green Deployment</h1><p>Application connected to RDS database my_db.</p></body></html>' > /usr/share/nginx/html/index.html
EXPOSE 80
EOF
}

data "archive_file" "elastic_beanstalk_application_zip" {
  type        = "zip"
  source_dir  = "${path.module}/eb-app"
  output_path = "${path.module}/eb-app.zip"

  depends_on = [
    local_file.dockerfile
  ]
}

resource "aws_s3_object" "elastic_beanstalk_application_bundle" {
  bucket = aws_s3_bucket.elastic_beanstalk_source.id
  key    = "eb-app/blue-green-app.zip"
  source = data.archive_file.elastic_beanstalk_application_zip.output_path
  etag   = data.archive_file.elastic_beanstalk_application_zip.output_md5

  depends_on = [
    aws_s3_bucket_ownership_controls.elastic_beanstalk_source,
    aws_s3_bucket_public_access_block.elastic_beanstalk_source
  ]
}

resource "aws_elastic_beanstalk_application" "blue_green_app" {
  name        = "blue-green-eb-app"
  description = "Elastic Beanstalk application for blue/green deployment with RDS database"

  tags = {
    Name = "blue-green-eb-app"
  }
}

resource "aws_elastic_beanstalk_application_version" "app_version" {
  name        = "v1"
  application = aws_elastic_beanstalk_application.blue_green_app.name
  description = "Initial application version for blue/green deployment"

  bucket = aws_s3_bucket.elastic_beanstalk_source.id
  key    = aws_s3_object.elastic_beanstalk_application_bundle.key

  depends_on = [
    aws_s3_object.elastic_beanstalk_application_bundle
  ]

  tags = {
    Name = "blue-green-eb-app-v1"
  }
}

resource "aws_elastic_beanstalk_environment" "blue" {
  name                = "blue-eb-environment"
  application         = aws_elastic_beanstalk_application.blue_green_app.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.3.1 running Docker"
  version_label       = aws_elastic_beanstalk_application_version.app_version.name

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
    value     = aws_iam_instance_profile.ec2_eb_profile1.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = var.eb_instance_type
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.elastic_beanstalk_instances.id
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
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_HOST"
    value     = aws_db_instance.my_db.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_PORT"
    value     = tostring(aws_db_instance.my_db.port)
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_NAME"
    value     = aws_db_instance.my_db.db_name
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
    aws_db_snapshot.pre_deployment,
    aws_iam_role_policy_attachment.elastic_beanstalk_service_role_enhanced_health,
    aws_iam_role_policy_attachment.elastic_beanstalk_service_role_managed_updates,
    aws_iam_role_policy_attachment.elastic_beanstalk_web_tier,
    aws_iam_instance_profile.ec2_eb_profile1
  ]

  tags = {
    Name        = "blue-eb-environment"
    Deployment  = "blue"
    Database    = "my_db"
    Snapshot    = aws_db_snapshot.pre_deployment.db_snapshot_identifier
  }
}

resource "aws_elastic_beanstalk_environment" "green" {
  name                = "green-eb-environment"
  application         = aws_elastic_beanstalk_application.blue_green_app.name
  solution_stack_name = "64bit Amazon Linux 2023 v4.3.1 running Docker"
  version_label       = aws_elastic_beanstalk_application_version.app_version.name

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
    value     = aws_iam_instance_profile.ec2_eb_profile1.name
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "InstanceType"
    value     = var.eb_instance_type
  }

  setting {
    namespace = "aws:autoscaling:launchconfiguration"
    name      = "SecurityGroups"
    value     = aws_security_group.elastic_beanstalk_instances.id
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
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_HOST"
    value     = aws_db_instance.my_db.address
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_PORT"
    value     = tostring(aws_db_instance.my_db.port)
  }

  setting {
    namespace = "aws:elasticbeanstalk:application:environment"
    name      = "DB_NAME"
    value     = aws_db_instance.my_db.db_name
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
    aws_db_snapshot.pre_deployment,
    aws_iam_role_policy_attachment.elastic_beanstalk_service_role_enhanced_health,
    aws_iam_role_policy_attachment.elastic_beanstalk_service_role_managed_updates,
    aws_iam_role_policy_attachment.elastic_beanstalk_web_tier,
    aws_iam_instance_profile.ec2_eb_profile1
  ]

  tags = {
    Name        = "green-eb-environment"
    Deployment  = "green"
    Database    = "my_db"
    Snapshot    = aws_db_snapshot.pre_deployment.db_snapshot_identifier
  }
}

output "database_name" {
  description = "The RDS database name."
  value       = aws_db_instance.my_db.db_name
}

output "database_endpoint" {
  description = "The RDS database endpoint."
  value       = aws_db_instance.my_db.endpoint
}

output "pre_deployment_snapshot_identifier" {
  description = "The snapshot taken before Elastic Beanstalk environment deployment."
  value       = aws_db_snapshot.pre_deployment.db_snapshot_identifier
}

output "elastic_beanstalk_instance_profile" {
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
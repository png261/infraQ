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
  region = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources."
  type        = string
  default     = "msk-debezium-demo"
}

variable "kafka_version" {
  description = "Kafka version for the MSK cluster."
  type        = string
  default     = "3.5.1"
}

variable "broker_instance_type" {
  description = "Instance type for MSK broker nodes."
  type        = string
  default     = "kafka.t3.small"
}

variable "connector_class" {
  description = "Fully qualified connector class from the Debezium plugin."
  type        = string
  default     = "io.debezium.connector.mysql.MySqlConnector"
}

variable "source_database_hostname" {
  description = "Hostname or IP address of the source database for Debezium."
  type        = string
  default     = "10.0.0.10"
}

variable "source_database_port" {
  description = "Source database port."
  type        = string
  default     = "3306"
}

variable "source_database_user" {
  description = "Source database user."
  type        = string
  default     = "debezium"
}

variable "source_database_password" {
  description = "Source database password."
  type        = string
  sensitive   = true
  default     = "ChangeMe123!"
}

variable "source_database_server_id" {
  description = "Unique MySQL server ID used by Debezium."
  type        = string
  default     = "184054"
}

variable "source_database_include_list" {
  description = "Comma-separated list of source databases to include."
  type        = string
  default     = "inventory"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "random_id" "suffix" {
  byte_length = 4
}

locals {
  name_suffix = "${var.project_name}-${random_id.suffix.hex}"

  private_subnet_cidrs = [
    "10.20.1.0/24",
    "10.20.2.0/24",
    "10.20.3.0/24"
  ]

  selected_azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${local.name_suffix}-vpc"
  }
}

resource "aws_subnet" "private" {
  count = 3

  vpc_id                  = aws_vpc.main.id
  cidr_block              = local.private_subnet_cidrs[count.index]
  availability_zone       = local.selected_azs[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${local.name_suffix}-private-${count.index + 1}"
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_suffix}-private-rt"
  }
}

resource "aws_route_table_association" "private" {
  count = 3

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

resource "aws_security_group" "msk" {
  name        = "${local.name_suffix}-msk-sg"
  description = "Security group for MSK brokers"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Allow plaintext Kafka traffic from MSK Connect"
    from_port       = 9092
    to_port         = 9092
    protocol        = "tcp"
    security_groups = [aws_security_group.msk_connect.id]
  }

  ingress {
    description = "Allow broker-to-broker communication within the MSK security group"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
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
    Name = "${local.name_suffix}-msk-sg"
  }
}

resource "aws_security_group" "msk_connect" {
  name        = "${local.name_suffix}-msk-connect-sg"
  description = "Security group for MSK Connect workers"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow all outbound traffic from MSK Connect"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_suffix}-msk-connect-sg"
  }
}

resource "aws_msk_cluster" "main" {
  cluster_name           = "${local.name_suffix}-cluster"
  kafka_version          = var.kafka_version
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = aws_subnet.private[*].id
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = 20
      }
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "PLAINTEXT"
      in_cluster    = true
    }
  }

  client_authentication {
    unauthenticated = true
  }

  tags = {
    Name = "${local.name_suffix}-cluster"
  }
}

resource "aws_s3_bucket" "plugins" {
  bucket        = "${local.name_suffix}-plugins"
  force_destroy = true

  tags = {
    Name = "${local.name_suffix}-plugins"
  }
}

resource "aws_s3_bucket_public_access_block" "plugins" {
  bucket = aws_s3_bucket.plugins.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "plugins" {
  bucket = aws_s3_bucket.plugins.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "debezium_zip" {
  bucket = aws_s3_bucket.plugins.id
  key    = "plugins/debezium.zip"
  source = "${path.module}/debezium.zip"

  etag = filemd5("${path.module}/debezium.zip")

  depends_on = [
    aws_s3_bucket_public_access_block.plugins,
    aws_s3_bucket_server_side_encryption_configuration.plugins
  ]
}

resource "aws_mskconnect_custom_plugin" "debezium" {
  name         = "${local.name_suffix}-debezium-plugin"
  content_type = "ZIP"

  location {
    s3 {
      bucket_arn = aws_s3_bucket.plugins.arn
      file_key   = aws_s3_object.debezium_zip.key
    }
  }

  tags = {
    Name = "${local.name_suffix}-debezium-plugin"
  }
}

resource "aws_cloudwatch_log_group" "msk_connect" {
  name              = "/aws/mskconnect/${local.name_suffix}"
  retention_in_days = 14

  tags = {
    Name = "${local.name_suffix}-msk-connect-logs"
  }
}

resource "aws_iam_role" "msk_connect" {
  name = "${local.name_suffix}-msk-connect-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "kafkaconnect.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${local.name_suffix}-msk-connect-role"
  }
}

resource "aws_iam_role_policy" "msk_connect" {
  name = "${local.name_suffix}-msk-connect-policy"
  role = aws_iam_role.msk_connect.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "MSKClusterAccess"
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeCluster",
          "kafka-cluster:AlterCluster",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:CreateTopic",
          "kafka-cluster:AlterTopic",
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData",
          "kafka-cluster:DescribeGroup",
          "kafka-cluster:AlterGroup"
        ]
        Resource = [
          aws_msk_cluster.main.arn,
          "${aws_msk_cluster.main.arn}/*"
        ]
      },
      {
        Sid    = "S3PluginAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.plugins.arn,
          "${aws_s3_bucket.plugins.arn}/*"
        ]
      },
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogDelivery",
          "logs:GetLogDelivery",
          "logs:UpdateLogDelivery",
          "logs:DeleteLogDelivery",
          "logs:ListLogDeliveries",
          "logs:PutResourcePolicy",
          "logs:DescribeResourcePolicies",
          "logs:DescribeLogGroups",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      },
      {
        Sid    = "EC2NetworkingAccess"
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
          "ec2:DeleteNetworkInterface"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_mskconnect_connector" "debezium" {
  name                 = "${local.name_suffix}-debezium-connector"
  kafkaconnect_version = "2.7.1"
  service_execution_role_arn = aws_iam_role.msk_connect.arn

  capacity {
    provisioned_capacity {
      mcu_count    = 1
      worker_count = 1
    }
  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = aws_msk_cluster.main.bootstrap_brokers

      vpc {
        subnets         = aws_subnet.private[*].id
        security_groups = [aws_security_group.msk_connect.id]
      }
    }
  }

  kafka_cluster_client_authentication {
    authentication_type = "NONE"
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = "PLAINTEXT"
  }

  plugin {
    custom_plugin {
      arn      = aws_mskconnect_custom_plugin.debezium.arn
      revision = aws_mskconnect_custom_plugin.debezium.latest_revision
    }
  }

  log_delivery {
    worker_log_delivery {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk_connect.name
      }
    }
  }

  connector_configuration = {
    "connector.class" = var.connector_class
    "tasks.max"       = "1"

    "database.hostname" = var.source_database_hostname
    "database.port"     = var.source_database_port
    "database.user"     = var.source_database_user
    "database.password" = var.source_database_password

    "database.server.id" = var.source_database_server_id

    "topic.prefix"           = "debezium"
    "database.include.list"  = var.source_database_include_list
    "schema.history.internal.kafka.bootstrap.servers" = aws_msk_cluster.main.bootstrap_brokers
    "schema.history.internal.kafka.topic"             = "schema-changes.inventory"

    "include.schema.changes" = "true"

    "key.converter"                  = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter"                = "org.apache.kafka.connect.json.JsonConverter"
    "key.converter.schemas.enable"   = "false"
    "value.converter.schemas.enable" = "false"

    "offset.storage.topic"        = "${local.name_suffix}-offsets"
    "config.storage.topic"        = "${local.name_suffix}-configs"
    "status.storage.topic"        = "${local.name_suffix}-status"
    "offset.storage.replication.factor" = "3"
    "config.storage.replication.factor" = "3"
    "status.storage.replication.factor" = "3"
  }

  depends_on = [
    aws_msk_cluster.main,
    aws_mskconnect_custom_plugin.debezium,
    aws_iam_role_policy.msk_connect,
    aws_cloudwatch_log_group.msk_connect
  ]

  tags = {
    Name = "${local.name_suffix}-debezium-connector"
  }
}

output "msk_cluster_name" {
  description = "Name of the MSK cluster."
  value       = aws_msk_cluster.main.cluster_name
}

output "msk_bootstrap_brokers" {
  description = "Plaintext bootstrap brokers for the MSK cluster."
  value       = aws_msk_cluster.main.bootstrap_brokers
}

output "msk_connect_custom_plugin_arn" {
  description = "ARN of the MSK Connect custom plugin."
  value       = aws_mskconnect_custom_plugin.debezium.arn
}

output "msk_connect_connector_arn" {
  description = "ARN of the MSK Connect connector."
  value       = aws_mskconnect_connector.debezium.arn
}
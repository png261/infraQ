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
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "msk-debezium-demo"
}

variable "kafka_version" {
  type    = string
  default = "3.6.0"
}

variable "broker_instance_type" {
  type    = string
  default = "kafka.t3.small"
}

variable "broker_ebs_volume_size" {
  type    = number
  default = 20
}

variable "debezium_plugin_zip_path" {
  type        = string
  description = "Local path to the Debezium MSK Connect plugin ZIP file."
  default     = "debezium.zip"
}

variable "connector_worker_count" {
  type    = number
  default = 1
}

resource "random_id" "suffix" {
  byte_length = 4
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_suffix = "${var.project_name}-${random_id.suffix.hex}"

  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  common_tags = {
    Project   = var.project_name
    ManagedBy = "Terraform"
  }
}

# -----------------------------
# Networking
# -----------------------------

resource "aws_vpc" "main" {
  cidr_block           = "10.60.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, {
    Name = "${local.name_suffix}-vpc"
  })
}

resource "aws_subnet" "private" {
  count = 3

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(aws_vpc.main.cidr_block, 8, count.index + 1)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, {
    Name = "${local.name_suffix}-private-${count.index + 1}"
  })
}

resource "aws_security_group" "msk" {
  name        = "${local.name_suffix}-msk-sg"
  description = "Security group for MSK cluster and MSK Connect"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Kafka TLS from same security group"
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Kafka plaintext from same security group"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "JMX exporter from same security group"
    from_port   = 11001
    to_port     = 11001
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Node exporter from same security group"
    from_port   = 11002
    to_port     = 11002
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

  tags = merge(local.common_tags, {
    Name = "${local.name_suffix}-msk-sg"
  })
}

# -----------------------------
# KMS encryption for MSK at rest
# -----------------------------

resource "aws_kms_key" "msk" {
  description             = "KMS key for MSK encryption at rest"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = merge(local.common_tags, {
    Name = "${local.name_suffix}-msk-kms"
  })
}

resource "aws_kms_alias" "msk" {
  name          = "alias/${local.name_suffix}-msk"
  target_key_id = aws_kms_key.msk.key_id
}

# -----------------------------
# Logging destinations
# -----------------------------

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${local.name_suffix}"
  retention_in_days = 14

  tags = local.common_tags
}

resource "aws_s3_bucket" "msk_logs" {
  bucket        = "${local.name_suffix}-msk-logs"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${local.name_suffix}-msk-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "msk_logs" {
  bucket = aws_s3_bucket.msk_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "msk_logs" {
  bucket = aws_s3_bucket.msk_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket" "firehose_logs" {
  bucket        = "${local.name_suffix}-firehose-logs"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${local.name_suffix}-firehose-logs"
  })
}

resource "aws_s3_bucket_public_access_block" "firehose_logs" {
  bucket = aws_s3_bucket.firehose_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "firehose_logs" {
  bucket = aws_s3_bucket.firehose_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_iam_role" "firehose" {
  name = "${local.name_suffix}-firehose-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy" "firehose" {
  name = "${local.name_suffix}-firehose-policy"
  role = aws_iam_role.firehose.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [
          aws_s3_bucket.firehose_logs.arn,
          "${aws_s3_bucket.firehose_logs.arn}/*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kinesis_firehose_delivery_stream" "msk_logs" {
  name        = "${local.name_suffix}-msk-broker-logs"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn           = aws_iam_role.firehose.arn
    bucket_arn         = aws_s3_bucket.firehose_logs.arn
    prefix             = "msk-broker-logs/!{timestamp:yyyy/MM/dd/HH}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/!{timestamp:yyyy/MM/dd/HH}/"
    buffering_size     = 5
    buffering_interval = 300
    compression_format = "GZIP"
  }

  tags = local.common_tags
}

# -----------------------------
# MSK Cluster
# -----------------------------

resource "aws_msk_cluster" "main" {
  cluster_name           = local.name_suffix
  kafka_version          = var.kafka_version
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type   = var.broker_instance_type
    client_subnets  = aws_subnet.private[*].id
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.broker_ebs_volume_size
      }
    }
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.msk.arn

    encryption_in_transit {
      client_broker = "TLS_PLAINTEXT"
      in_cluster    = true
    }
  }

  client_authentication {
    unauthenticated = true
  }

  open_monitoring {
    prometheus {
      jmx_exporter {
        enabled_in_broker = true
      }

      node_exporter {
        enabled_in_broker = true
      }
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }

      s3 {
        enabled = true
        bucket  = aws_s3_bucket.msk_logs.id
        prefix  = "broker-logs/"
      }

      firehose {
        enabled         = true
        delivery_stream = aws_kinesis_firehose_delivery_stream.msk_logs.name
      }
    }
  }

  tags = local.common_tags

  depends_on = [
    aws_iam_role_policy.firehose,
    aws_s3_bucket_public_access_block.msk_logs,
    aws_s3_bucket_public_access_block.firehose_logs
  ]
}

# -----------------------------
# MSK Connect plugin artifact bucket
# -----------------------------

resource "aws_s3_bucket" "connect_plugins" {
  bucket        = "${local.name_suffix}-connect-plugins"
  force_destroy = true

  tags = merge(local.common_tags, {
    Name = "${local.name_suffix}-connect-plugins"
  })
}

resource "aws_s3_bucket_public_access_block" "connect_plugins" {
  bucket = aws_s3_bucket.connect_plugins.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "connect_plugins" {
  bucket = aws_s3_bucket.connect_plugins.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "debezium_zip" {
  bucket = aws_s3_bucket.connect_plugins.id
  key    = "plugins/debezium.zip"
  source = var.debezium_plugin_zip_path
  etag   = filemd5(var.debezium_plugin_zip_path)

  tags = local.common_tags
}

resource "aws_mskconnect_custom_plugin" "debezium" {
  name         = "${local.name_suffix}-debezium"
  content_type = "ZIP"

  location {
    s3 {
      bucket_arn = aws_s3_bucket.connect_plugins.arn
      file_key   = aws_s3_object.debezium_zip.key
    }
  }

  tags = local.common_tags
}

# -----------------------------
# MSK Connect service execution role
# -----------------------------

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

  tags = local.common_tags
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
          "kafka-cluster:DescribeClusterDynamicConfiguration",
          "kafka-cluster:AlterCluster",
          "kafka-cluster:WriteData",
          "kafka-cluster:ReadData",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:CreateTopic",
          "kafka-cluster:AlterTopic",
          "kafka-cluster:DescribeGroup",
          "kafka-cluster:AlterGroup"
        ]
        Resource = [
          aws_msk_cluster.main.arn,
          "${replace(aws_msk_cluster.main.arn, ":cluster/", ":topic/")}/*",
          "${replace(aws_msk_cluster.main.arn, ":cluster/", ":group/")}/*"
        ]
      },
      {
        Sid    = "PluginArtifactReadAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.connect_plugins.arn,
          "${aws_s3_bucket.connect_plugins.arn}/*"
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
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_cloudwatch_log_group" "msk_connect" {
  name              = "/aws/mskconnect/${local.name_suffix}"
  retention_in_days = 14

  tags = local.common_tags
}

# -----------------------------
# MSK Connect connector
# -----------------------------

resource "aws_mskconnect_connector" "debezium" {
  name                 = "${local.name_suffix}-debezium-connector"
  kafkaconnect_version = "2.7.1"
  service_execution_role_arn = aws_iam_role.msk_connect.arn

  capacity {
    provisioned_capacity {
      worker_count    = var.connector_worker_count
      mcu_count       = 1
    }
  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = aws_msk_cluster.main.bootstrap_brokers_tls

      vpc {
        subnets         = aws_subnet.private[*].id
        security_groups = [aws_security_group.msk.id]
      }
    }
  }

  kafka_cluster_client_authentication {
    authentication_type = "NONE"
  }

  kafka_cluster_encryption_in_transit {
    encryption_type = "TLS"
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
    "connector.class" = "io.debezium.connector.mysql.MySqlConnector"
    "tasks.max"       = "1"

    "database.hostname" = "example-mysql.internal"
    "database.port"     = "3306"
    "database.user"     = "debezium"
    "database.password" = "debezium-password"

    "database.server.id"   = "184054"
    "database.server.name" = "exampledb"

    "database.include.list" = "exampledb"
    "table.include.list"    = "exampledb.example_table"

    "include.schema.changes" = "true"

    "topic.prefix" = "exampledb"

    "schema.history.internal.kafka.bootstrap.servers" = aws_msk_cluster.main.bootstrap_brokers_tls
    "schema.history.internal.kafka.topic"             = "schema-changes.exampledb"

    "key.converter"                  = "org.apache.kafka.connect.json.JsonConverter"
    "value.converter"                = "org.apache.kafka.connect.json.JsonConverter"
    "key.converter.schemas.enable"   = "false"
    "value.converter.schemas.enable" = "false"
  }

  tags = local.common_tags

  depends_on = [
    aws_msk_cluster.main,
    aws_mskconnect_custom_plugin.debezium,
    aws_iam_role_policy.msk_connect
  ]
}

# -----------------------------
# Outputs
# -----------------------------

output "msk_cluster_arn" {
  value = aws_msk_cluster.main.arn
}

output "msk_cluster_name" {
  value = aws_msk_cluster.main.cluster_name
}

output "msk_bootstrap_brokers_tls" {
  value = aws_msk_cluster.main.bootstrap_brokers_tls
}

output "msk_cloudwatch_log_group" {
  value = aws_cloudwatch_log_group.msk.name
}

output "msk_s3_log_bucket" {
  value = aws_s3_bucket.msk_logs.bucket
}

output "msk_firehose_delivery_stream" {
  value = aws_kinesis_firehose_delivery_stream.msk_logs.name
}

output "msk_connect_plugin_arn" {
  value = aws_mskconnect_custom_plugin.debezium.arn
}

output "msk_connect_connector_arn" {
  value = aws_mskconnect_connector.debezium.arn
}
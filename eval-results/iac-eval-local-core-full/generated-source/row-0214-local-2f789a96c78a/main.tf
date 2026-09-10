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

variable "debezium_plugin_zip_source" {
  description = "Local path to the Debezium MSK Connect custom plugin ZIP. The benchmark default preserves the required debezium.zip artifact name."
  type        = string
  default     = "debezium.zip"
}

variable "debezium_database_hostname" {
  description = "PostgreSQL database hostname for the Debezium connector. The endpoint must be reachable from the connector subnets in this VPC, for example a private database endpoint, peered/transit-routed endpoint, or resolvable private DNS name."
  type        = string
  default     = "postgres.example.internal"
}

variable "debezium_database_port" {
  description = "PostgreSQL database port for the Debezium connector. Ensure security groups and routing allow this port from the connector subnets."
  type        = string
  default     = "5432"
}

variable "debezium_database_user" {
  description = "PostgreSQL database user for the Debezium connector."
  type        = string
  default     = "debezium"
}

variable "debezium_database_password_secret_arn" {
  description = "ARN of an existing AWS Secrets Manager secret containing the PostgreSQL password under JSON key 'password'. The connector references this at runtime through the MSK Connect Secrets Manager config provider so the plaintext password is not stored in Terraform state."
  type        = string
}

variable "debezium_database_name" {
  description = "PostgreSQL database name for the Debezium connector."
  type        = string
  default     = "postgres"
}

variable "debezium_topic_prefix" {
  description = "Topic prefix/server name used by Debezium for emitted change event topics."
  type        = string
  default     = "iac-eval-postgres"
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name = "iac-eval-msk"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = local.name
  }
}

resource "aws_subnet" "broker_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${local.name}-broker-a"
  }
}

resource "aws_subnet" "broker_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${local.name}-broker-b"
  }
}

resource "aws_subnet" "broker_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = data.aws_availability_zones.available.names[2]

  tags = {
    Name = "${local.name}-broker-c"
  }
}

resource "aws_security_group" "msk" {
  name        = "${local.name}-sg"
  description = "Allow MSK and MSK Connect traffic within the benchmark VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Kafka TLS within VPC"
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  ingress {
    description = "PostgreSQL source access within VPC"
    from_port   = tonumber(var.debezium_database_port)
    to_port     = tonumber(var.debezium_database_port)
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.main.cidr_block]
  }

  egress {
    description = "Allow outbound traffic to MSK, reachable private source endpoints, and AWS service endpoints"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name}-sg"
  }
}

resource "aws_kms_key" "msk" {
  description             = "KMS key for MSK encryption at rest"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${local.name}"
  retention_in_days = 7
}

resource "aws_s3_bucket" "logs" {
  bucket_prefix = "${local.name}-logs-"
}

resource "aws_s3_bucket" "plugins" {
  bucket_prefix = "${local.name}-plugins-"
}

resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    object_ownership = "ObjectWriter"
  }
}

resource "aws_s3_bucket_acl" "logs" {
  depends_on = [aws_s3_bucket_ownership_controls.logs]

  bucket = aws_s3_bucket.logs.id
  acl    = "private"
}

resource "aws_s3_object" "debezium_plugin" {
  bucket = aws_s3_bucket.plugins.id
  key    = "debezium.zip"
  source = var.debezium_plugin_zip_source
}

data "aws_iam_policy_document" "firehose_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose" {
  name               = "${local.name}-firehose-role"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role.json

  inline_policy {
    name = "write-msk-logs-to-s3"

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
            aws_s3_bucket.logs.arn,
            "${aws_s3_bucket.logs.arn}/*"
          ]
        }
      ]
    })
  }
}

resource "aws_kinesis_firehose_delivery_stream" "msk_logs" {
  name        = "${local.name}-broker-logs"
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = aws_s3_bucket.logs.arn
  }
}

data "aws_iam_policy_document" "msk_connect_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["kafkaconnect.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "msk_connect_access" {
  statement {
    actions = [
      "kafka-cluster:Connect",
      "kafka-cluster:DescribeCluster",
      "kafka-cluster:ReadData",
      "kafka-cluster:WriteData",
      "kafka-cluster:CreateTopic",
      "kafka-cluster:DescribeTopic",
      "kafka-cluster:AlterGroup",
      "kafka-cluster:DescribeGroup"
    ]
    resources = ["*"]
  }

  statement {
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion"
    ]
    resources = ["${aws_s3_bucket.plugins.arn}/*"]
  }

  statement {
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [var.debezium_database_password_secret_arn]
  }

  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role" "msk_connect" {
  name               = "${local.name}-connect-role"
  assume_role_policy = data.aws_iam_policy_document.msk_connect_assume_role.json

  inline_policy {
    name   = "msk-connect-access"
    policy = data.aws_iam_policy_document.msk_connect_access.json
  }
}

resource "aws_msk_cluster" "main" {
  cluster_name           = local.name
  kafka_version          = "3.5.1"
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type   = "kafka.t3.small"
    client_subnets  = [aws_subnet.broker_a.id, aws_subnet.broker_b.id, aws_subnet.broker_c.id]
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = 20
      }
    }
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.msk.arn
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }

      s3 {
        enabled = true
        bucket  = aws_s3_bucket.logs.id
        prefix  = "msk/"
      }

      firehose {
        enabled         = true
        delivery_stream = aws_kinesis_firehose_delivery_stream.msk_logs.name
      }
    }
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
}

resource "aws_mskconnect_custom_plugin" "debezium" {
  name         = "${local.name}-debezium"
  content_type = "ZIP"

  location {
    s3 {
      bucket_arn = aws_s3_bucket.plugins.arn
      file_key   = aws_s3_object.debezium_plugin.key
    }
  }
}

resource "aws_mskconnect_connector" "debezium" {
  name                       = "${local.name}-connector"
  kafkaconnect_version       = "2.7.1"
  service_execution_role_arn = aws_iam_role.msk_connect.arn

  capacity {
    provisioned_capacity {
      mcu_count    = 1
      worker_count = 1
    }
  }

  connector_configuration = {
    "connector.class"                                      = "io.debezium.connector.postgresql.PostgresConnector"
    "tasks.max"                                            = "1"
    "database.hostname"                                    = var.debezium_database_hostname
    "database.port"                                        = var.debezium_database_port
    "database.user"                                        = var.debezium_database_user
    "database.password"                                    = "$${secretsmanager:${var.debezium_database_password_secret_arn}:password}"
    "database.dbname"                                      = var.debezium_database_name
    "topic.prefix"                                         = var.debezium_topic_prefix
    "plugin.name"                                          = "pgoutput"
    "slot.name"                                            = "iac_eval_debezium"
    "publication.name"                                     = "iac_eval_publication"
    "publication.autocreate.mode"                          = "filtered"
    "config.providers"                                     = "secretsmanager"
    "config.providers.secretsmanager.class"                = "software.amazon.msk.config.providers.SecretsManagerConfigProvider"
    "schema.history.internal.kafka.bootstrap.servers"      = aws_msk_cluster.main.bootstrap_brokers_tls
    "schema.history.internal.kafka.topic"                   = "${var.debezium_topic_prefix}.schema-history"
  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = aws_msk_cluster.main.bootstrap_brokers_tls

      vpc {
        security_groups = [aws_security_group.msk.id]
        subnets         = [aws_subnet.broker_a.id, aws_subnet.broker_b.id, aws_subnet.broker_c.id]
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
        log_group = aws_cloudwatch_log_group.msk.name
      }
    }
  }
}

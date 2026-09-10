data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "iac-eval-msk-connect"
}

variable "database_hostname" {
  description = "PostgreSQL database hostname for the Debezium connector. Replace the placeholder before applying."
  type        = string
  default     = "postgres.example.internal"
}

variable "database_port" {
  description = "PostgreSQL database port for the Debezium connector."
  type        = number
  default     = 5432
}

variable "database_user" {
  description = "PostgreSQL database username for the Debezium connector."
  type        = string
  default     = "debezium"
}

variable "database_password" {
  description = "PostgreSQL database password for the Debezium connector. Supply a real value through tfvars or TF_VAR_database_password before applying."
  type        = string
  sensitive   = true
  default     = "change-me"
}

variable "database_name" {
  description = "PostgreSQL database name for the Debezium connector."
  type        = string
  default     = "appdb"
}

variable "database_server_name" {
  description = "Logical server name used by Debezium for topic naming."
  type        = string
  default     = "postgres-server"
}

variable "topic_prefix" {
  description = "Topic prefix used by Debezium PostgreSQL connector."
  type        = string
  default     = "postgres"
}

variable "plugin_name" {
  description = "PostgreSQL logical decoding plugin name used by Debezium."
  type        = string
  default     = "pgoutput"
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = local.name_prefix
  }
}

resource "aws_subnet" "broker_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "${local.name_prefix}-broker-a"
  }
}

resource "aws_subnet" "broker_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "${local.name_prefix}-broker-b"
  }
}

resource "aws_subnet" "broker_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = data.aws_availability_zones.available.names[2]

  tags = {
    Name = "${local.name_prefix}-broker-c"
  }
}

resource "aws_security_group" "msk" {
  name        = "${local.name_prefix}-sg"
  description = "Allow MSK brokers and MSK Connect workers to communicate"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Kafka plaintext traffic within this security group"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    self        = true
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-sg"
  }
}

resource "aws_iam_role" "msk_connect" {
  name = "${local.name_prefix}-service-role"

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
}

resource "aws_iam_role_policy" "msk_connect" {
  name = "${local.name_prefix}-service-policy"
  role = aws_iam_role.msk_connect.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kafka-cluster:Connect",
          "kafka-cluster:DescribeCluster",
          "kafka-cluster:ReadData",
          "kafka-cluster:WriteData",
          "kafka-cluster:CreateTopic",
          "kafka-cluster:DescribeTopic",
          "kafka-cluster:AlterGroup",
          "kafka-cluster:DescribeGroup"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateNetworkInterface",
          "ec2:CreateNetworkInterfacePermission",
          "ec2:DeleteNetworkInterface",
          "ec2:DescribeAvailabilityZones",
          "ec2:DescribeNetworkInterfaces",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeVpcs"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket"
        ]
        Resource = [
          aws_s3_bucket.plugin.arn,
          "${aws_s3_bucket.plugin.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_s3_bucket" "plugin" {
  bucket_prefix = "iac-eval-msk-plugin-"

  tags = {
    Name = "${local.name_prefix}-plugin"
  }
}

resource "aws_s3_object" "debezium" {
  bucket      = aws_s3_bucket.plugin.id
  key         = "debezium.zip"
  source      = "${path.module}/debezium.zip"
  source_hash = filemd5("${path.module}/debezium.zip")
  content_type = "application/zip"
}

resource "aws_msk_cluster" "main" {
  cluster_name           = local.name_prefix
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

  client_authentication {
    unauthenticated = true
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "PLAINTEXT"
      in_cluster    = true
    }
  }
}

resource "aws_mskconnect_custom_plugin" "debezium" {
  name         = "${local.name_prefix}-debezium"
  content_type = "ZIP"

  location {
    s3 {
      bucket_arn = aws_s3_bucket.plugin.arn
      file_key   = "debezium.zip"
    }
  }

  depends_on = [aws_s3_object.debezium]
}

resource "aws_mskconnect_connector" "debezium" {
  name                       = "${local.name_prefix}-connector"
  kafkaconnect_version       = "2.7.1"
  service_execution_role_arn = aws_iam_role.msk_connect.arn

  capacity {
    provisioned_capacity {
      mcu_count    = 1
      worker_count = 1
    }
  }

  connector_configuration = {
    "connector.class"    = "io.debezium.connector.postgresql.PostgresConnector"
    "tasks.max"          = "1"
    "database.hostname"  = var.database_hostname
    "database.port"      = tostring(var.database_port)
    "database.user"      = var.database_user
    "database.password"  = var.database_password
    "database.dbname"    = var.database_name
    "database.server.name" = var.database_server_name
    "topic.prefix"       = var.topic_prefix
    "plugin.name"        = var.plugin_name
    "slot.name"          = "debezium"
    "publication.name"   = "dbz_publication"
  }

  kafka_cluster {
    apache_kafka_cluster {
      bootstrap_servers = aws_msk_cluster.main.bootstrap_brokers

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
    encryption_type = "PLAINTEXT"
  }

  plugin {
    custom_plugin {
      arn      = aws_mskconnect_custom_plugin.debezium.arn
      revision = aws_mskconnect_custom_plugin.debezium.latest_revision
    }
  }

  depends_on = [aws_iam_role_policy.msk_connect]
}

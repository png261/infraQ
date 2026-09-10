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
  description = "AWS region where the DAX cluster will be created."
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "Name of the DAX cluster."
  type        = string
  default     = "example-dax-cluster"
}

variable "node_type" {
  description = "DAX node instance type."
  type        = string
  default     = "dax.t3.small"
}

variable "replication_factor" {
  description = "Number of nodes in the DAX cluster."
  type        = number
  default     = 1
}

variable "allowed_cidr_blocks" {
  description = "CIDR blocks allowed to connect to the DAX cluster."
  type        = list(string)
  default     = ["10.0.0.0/8"]
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

data "aws_iam_policy_document" "dax_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["dax.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "dax_service_role" {
  name               = "${var.cluster_name}-service-role"
  assume_role_policy = data.aws_iam_policy_document.dax_assume_role.json
}

resource "aws_iam_role_policy_attachment" "dax_dynamodb_access" {
  role       = aws_iam_role.dax_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonDynamoDBFullAccess"
}

resource "aws_security_group" "dax" {
  name        = "${var.cluster_name}-sg"
  description = "Security group for DAX cluster"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "Allow DAX client access"
    from_port   = 8111
    to_port     = 8111
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.cluster_name}-sg"
  }
}

resource "aws_dax_subnet_group" "main" {
  name        = "${var.cluster_name}-subnet-group"
  description = "Subnet group for DAX cluster"
  subnet_ids  = data.aws_subnets.default.ids
}

resource "aws_dax_parameter_group" "main" {
  name        = "${var.cluster_name}-parameter-group"
  description = "Parameter group for DAX cluster"
}

resource "aws_dax_cluster" "main" {
  cluster_name       = var.cluster_name
  iam_role_arn       = aws_iam_role.dax_service_role.arn
  node_type          = var.node_type
  replication_factor = var.replication_factor

  subnet_group_name    = aws_dax_subnet_group.main.name
  parameter_group_name = aws_dax_parameter_group.main.name
  security_group_ids   = [aws_security_group.dax.id]

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name = var.cluster_name
  }

  depends_on = [
    aws_iam_role_policy_attachment.dax_dynamodb_access
  ]
}

output "dax_cluster_name" {
  description = "Name of the created DAX cluster."
  value       = aws_dax_cluster.main.cluster_name
}

output "dax_cluster_arn" {
  description = "ARN of the created DAX cluster."
  value       = aws_dax_cluster.main.arn
}

output "dax_cluster_discovery_endpoint" {
  description = "DAX cluster discovery endpoint."
  value       = aws_dax_cluster.main.cluster_address
}

output "dax_cluster_port" {
  description = "DAX cluster port."
  value       = aws_dax_cluster.main.port
}
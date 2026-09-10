terraform {
  required_version = ">= 1.6.0"

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

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "dolphinscheduler"

  common_tags = {
    Project = "dolphinscheduler"
  }
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-a"
    Tier = "public"
  })
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-b"
    Tier = "public"
  })
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.101.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-a"
    Tier = "private"
  })
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.102.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-b"
    Tier = "private"
  })
}

resource "aws_security_group" "master" {
  name        = "${local.name_prefix}-master"
  description = "DolphinScheduler master access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Master service from worker nodes"
    from_port   = 5678
    to_port     = 5678
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

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-master-sg"
  })
}

resource "aws_security_group" "worker" {
  name        = "${local.name_prefix}-worker"
  description = "DolphinScheduler worker access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Worker service from master nodes"
    from_port   = 1234
    to_port     = 1234
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

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-worker-sg"
  })
}

resource "aws_security_group" "alert" {
  name        = "${local.name_prefix}-alert"
  description = "DolphinScheduler alert service access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Alert service from application components"
    from_port   = 50052
    to_port     = 50052
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

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alert-sg"
  })
}

resource "aws_security_group" "api" {
  name        = "${local.name_prefix}-api"
  description = "DolphinScheduler API access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "API HTTP access from public subnets"
    from_port   = 12345
    to_port     = 12345
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.public_a.cidr_block, aws_subnet.public_b.cidr_block]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-api-sg"
  })
}

resource "aws_security_group" "standalone" {
  name        = "${local.name_prefix}-standalone"
  description = "DolphinScheduler standalone access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Standalone UI access from public subnets"
    from_port   = 12345
    to_port     = 12345
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.public_a.cidr_block, aws_subnet.public_b.cidr_block]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-standalone-sg"
  })
}

resource "aws_security_group" "database" {
  name        = "${local.name_prefix}-database"
  description = "PostgreSQL database access for DolphinScheduler components"
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from master"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.master.id]
  }

  ingress {
    description     = "PostgreSQL from worker"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.worker.id]
  }

  ingress {
    description     = "PostgreSQL from API"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.api.id]
  }

  ingress {
    description     = "PostgreSQL from standalone"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.standalone.id]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-database-sg"
  })
}

resource "aws_db_subnet_group" "database" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}

resource "aws_db_instance" "database" {
  identifier             = "dolphinscheduler"
  allocated_storage      = 5
  engine                 = "postgres"
  engine_version         = "17.1"
  instance_class         = var.db_instance_class
  db_name                = var.db_name
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.database.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false
  skip_final_snapshot    = true

  tags = merge(local.common_tags, {
    Name = "dolphinscheduler"
  })
}

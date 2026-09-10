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
  region = var.aws_region
}

############################
# Variables
############################

variable "aws_region" {
  description = "AWS region to deploy resources into."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_1_cidr" {
  description = "CIDR block for the first public subnet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "public_subnet_2_cidr" {
  description = "CIDR block for the second public subnet."
  type        = string
  default     = "10.0.2.0/24"
}

variable "db_allowed_cidr" {
  description = "CIDR block allowed to access PostgreSQL on port 5432."
  type        = string
  default     = "0.0.0.0/0"
}

variable "db_name" {
  description = "Initial PostgreSQL database name."
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "PostgreSQL administrator username."
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "PostgreSQL administrator password."
  type        = string
  sensitive   = true
  default     = "ChangeMe123!"
}

variable "instance_type" {
  description = "EC2 instance type for the PostgreSQL host."
  type        = string
  default     = "t3.micro"
}

############################
# Data Sources
############################

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "amazon_linux_2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

############################
# Networking
############################

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "postgres-vpc"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "postgres-vpc-igw"
  }
}

resource "aws_subnet" "public_1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_1_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "postgres-public-subnet-1"
  }
}

resource "aws_subnet" "public_2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_2_cidr
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "postgres-public-subnet-2"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "postgres-public-route-table"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_1" {
  subnet_id      = aws_subnet.public_1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_2" {
  subnet_id      = aws_subnet.public_2.id
  route_table_id = aws_route_table.public.id
}

############################
# Security Groups
############################

resource "aws_security_group" "postgres" {
  name        = "postgres-db-security-group"
  description = "Security group for PostgreSQL database access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "Allow PostgreSQL access"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.db_allowed_cidr]
  }

  egress {
    description = "Allow outbound access"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "postgres-db-security-group"
  }
}

############################
# IAM Role for EC2 / SSM
############################

resource "aws_iam_role" "ec2_ssm_role" {
  name = "postgres-ec2-ssm-role"

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
    Name = "postgres-ec2-ssm-role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "postgres-ec2-instance-profile"
  role = aws_iam_role.ec2_ssm_role.name
}

############################
# PostgreSQL EC2 Instance
############################

resource "aws_instance" "postgres" {
  ami                         = data.aws_ssm_parameter.amazon_linux_2023.value
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_1.id
  vpc_security_group_ids      = [aws_security_group.postgres.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -eux

    dnf update -y
    dnf install -y docker xfsprogs

    systemctl enable docker
    systemctl start docker

    mkdir -p /var/lib/postgresql-data

    # Wait for the attached EBS data volume to appear.
    for i in {1..30}; do
      DATA_DEVICE=$(lsblk -dpno NAME,TYPE | awk '$2=="disk"{print $1}' | grep -v "$(findmnt -n -o SOURCE / | sed 's/[0-9p]*$//')" | tail -n 1 || true)
      if [ -n "$DATA_DEVICE" ]; then
        break
      fi
      sleep 5
    done

    if [ -z "$DATA_DEVICE" ]; then
      echo "No data volume found"
      exit 1
    fi

    if ! blkid "$DATA_DEVICE"; then
      mkfs.xfs "$DATA_DEVICE"
    fi

    mount "$DATA_DEVICE" /var/lib/postgresql-data

    DATA_UUID=$(blkid -s UUID -o value "$DATA_DEVICE")
    echo "UUID=$DATA_UUID /var/lib/postgresql-data xfs defaults,nofail 0 2" >> /etc/fstab

    docker pull postgres:17.1

    docker run -d \
      --name postgres-17-1 \
      --restart unless-stopped \
      -e POSTGRES_DB="${var.db_name}" \
      -e POSTGRES_USER="${var.db_username}" \
      -e POSTGRES_PASSWORD="${var.db_password}" \
      -v /var/lib/postgresql-data:/var/lib/postgresql/data \
      -p 5432:5432 \
      postgres:17.1
  EOF

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "postgres-17-1-instance"
  }

  depends_on = [
    aws_route_table_association.public_1,
    aws_iam_role_policy_attachment.ssm_managed_instance_core
  ]
}

resource "aws_ebs_volume" "postgres_data" {
  availability_zone = aws_subnet.public_1.availability_zone
  size              = 5
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "postgres-5gb-data-volume"
  }
}

resource "aws_volume_attachment" "postgres_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.postgres_data.id
  instance_id = aws_instance.postgres.id
}

############################
# Outputs
############################

output "vpc_id" {
  description = "ID of the created VPC."
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets."
  value = [
    aws_subnet.public_1.id,
    aws_subnet.public_2.id
  ]
}

output "postgres_security_group_id" {
  description = "Security group ID for PostgreSQL access."
  value       = aws_security_group.postgres.id
}

output "postgres_public_ip" {
  description = "Public IP address of the PostgreSQL instance."
  value       = aws_instance.postgres.public_ip
}

output "postgres_endpoint" {
  description = "PostgreSQL connection endpoint."
  value       = "${aws_instance.postgres.public_ip}:5432"
}

output "postgres_version" {
  description = "PostgreSQL version deployed."
  value       = "17.1"
}

output "postgres_storage_capacity_gb" {
  description = "Dedicated PostgreSQL data volume capacity in GiB."
  value       = 5
}
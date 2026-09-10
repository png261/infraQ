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

variable "aws_region" {
  description = "AWS region where resources will be created."
  type        = string
  default     = "us-east-1"
}

variable "instance_count" {
  description = "Number of EC2 instances to launch in the placement group."
  type        = number
  default     = 3
}

variable "instance_type" {
  description = "EC2 instance type to use. c5.large supports placement groups."
  type        = string
  default     = "c5.large"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet."
  type        = string
  default     = "10.0.1.0/24"
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "amazon_linux_2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_vpc" "cluster_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "cluster-placement-vpc"
  }
}

resource "aws_internet_gateway" "cluster_igw" {
  vpc_id = aws_vpc.cluster_vpc.id

  tags = {
    Name = "cluster-placement-igw"
  }
}

resource "aws_subnet" "cluster_subnet" {
  vpc_id                  = aws_vpc.cluster_vpc.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "cluster-placement-subnet"
  }
}

resource "aws_route_table" "cluster_route_table" {
  vpc_id = aws_vpc.cluster_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cluster_igw.id
  }

  tags = {
    Name = "cluster-placement-route-table"
  }
}

resource "aws_route_table_association" "cluster_route_table_association" {
  subnet_id      = aws_subnet.cluster_subnet.id
  route_table_id = aws_route_table.cluster_route_table.id
}

resource "aws_security_group" "cluster_sg" {
  name        = "cluster-placement-sg"
  description = "Security group for EC2 cluster placement group instances"
  vpc_id      = aws_vpc.cluster_vpc.id

  ingress {
    description = "Allow all traffic between instances in this security group"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  ingress {
    description = "Allow SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound IPv4 traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cluster-placement-sg"
  }
}

resource "aws_iam_role" "ec2_ssm_role" {
  name = "cluster-placement-ec2-ssm-role"

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
    Name = "cluster-placement-ec2-ssm-role"
  }
}

resource "aws_iam_role_policy_attachment" "ssm_managed_instance_core" {
  role       = aws_iam_role.ec2_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_instance_profile" {
  name = "cluster-placement-ec2-instance-profile"
  role = aws_iam_role.ec2_ssm_role.name
}

resource "aws_placement_group" "cluster_pg" {
  name     = "ec2-cluster-placement-group"
  strategy = "cluster"

  tags = {
    Name = "ec2-cluster-placement-group"
  }
}

resource "aws_instance" "cluster_instances" {
  count = var.instance_count

  ami                         = data.aws_ami.amazon_linux_2023.id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.cluster_subnet.id
  vpc_security_group_ids      = [aws_security_group.cluster_sg.id]
  placement_group             = aws_placement_group.cluster_pg.name
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.ec2_instance_profile.name

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "cluster-placement-instance-${count.index + 1}"
  }

  depends_on = [
    aws_route_table_association.cluster_route_table_association,
    aws_iam_role_policy_attachment.ssm_managed_instance_core
  ]
}

output "placement_group_name" {
  description = "Name of the EC2 cluster placement group."
  value       = aws_placement_group.cluster_pg.name
}

output "instance_ids" {
  description = "IDs of the EC2 instances in the placement group."
  value       = aws_instance.cluster_instances[*].id
}

output "instance_private_ips" {
  description = "Private IP addresses of the EC2 instances."
  value       = aws_instance.cluster_instances[*].private_ip
}

output "instance_public_ips" {
  description = "Public IP addresses of the EC2 instances."
  value       = aws_instance.cluster_instances[*].public_ip
}

output "availability_zone" {
  description = "Availability Zone used for the clustered EC2 instances."
  value       = aws_subnet.cluster_subnet.availability_zone
}
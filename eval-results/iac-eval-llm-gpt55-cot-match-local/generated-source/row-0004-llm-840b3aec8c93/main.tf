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
  default = "us-west-2"
}

variable "dns_zone_name" {
  type    = string
  default = "example.com"
}

variable "database_record_name" {
  type    = string
  default = "database"
}

variable "db_username" {
  type    = string
  default = "adminuser"
}

data "aws_availability_zones" "available" {
  state = "available"
}

resource "random_password" "internal_db" {
  length  = 20
  special = false
}

resource "random_password" "public_db" {
  length  = 20
  special = false
}

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "main"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "main"
  }
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-a"
  }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = true

  tags = {
    Name = "public-b"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "public"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_db_subnet_group" "main" {
  name = "main"

  subnet_ids = [
    aws_subnet.public_a.id,
    aws_subnet.public_b.id
  ]

  tags = {
    Name = "main"
  }
}

resource "aws_security_group" "internal_db" {
  name        = "internal-db"
  description = "Allow MySQL access from inside the VPC"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "MySQL from VPC"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [
      aws_vpc.main.cidr_block
    ]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  tags = {
    Name = "internal-db"
  }
}

resource "aws_security_group" "public_db" {
  name        = "public-db"
  description = "Allow public MySQL access"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "MySQL from the internet"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [
      "0.0.0.0/0"
    ]
  }

  tags = {
    Name = "public-db"
  }
}

resource "aws_db_instance" "internal" {
  identifier = "internal"

  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = "internal"
  username               = var.db_username
  password               = random_password.internal_db.result
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.internal_db.id]

  publicly_accessible  = false
  skip_final_snapshot  = true
  deletion_protection  = false
  apply_immediately    = true
  storage_encrypted    = true
  multi_az             = false

  tags = {
    Name = "internal"
  }
}

resource "aws_db_instance" "public" {
  identifier = "public"

  allocated_storage      = 20
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = "public"
  username               = var.db_username
  password               = random_password.public_db.result
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.public_db.id]

  publicly_accessible  = true
  skip_final_snapshot  = true
  deletion_protection  = false
  apply_immediately    = true
  storage_encrypted    = true
  multi_az             = false

  tags = {
    Name = "public"
  }
}

resource "aws_route53_zone" "private" {
  name = var.dns_zone_name

  vpc {
    vpc_id = aws_vpc.main.id
  }

  comment = "Private hosted zone for internal database resolution"

  tags = {
    Name = "private"
  }
}

resource "aws_route53_zone" "public" {
  name = var.dns_zone_name

  comment = "Public hosted zone for external database resolution"

  tags = {
    Name = "public"
  }
}

resource "aws_route53_record" "private_database" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "${var.database_record_name}.${var.dns_zone_name}"
  type    = "CNAME"
  ttl     = 300

  records = [
    aws_db_instance.internal.address
  ]
}

resource "aws_route53_record" "public_database" {
  zone_id = aws_route53_zone.public.zone_id
  name    = "${var.database_record_name}.${var.dns_zone_name}"
  type    = "CNAME"
  ttl     = 300

  records = [
    aws_db_instance.public.address
  ]
}

output "internal_database_endpoint" {
  value = aws_db_instance.internal.endpoint
}

output "public_database_endpoint" {
  value = aws_db_instance.public.endpoint
}

output "private_dns_name" {
  value = aws_route53_record.private_database.fqdn
}

output "public_dns_name" {
  value = aws_route53_record.public_database.fqdn
}

output "public_zone_name_servers" {
  value = aws_route53_zone.public.name_servers
}

output "internal_db_password" {
  value     = random_password.internal_db.result
  sensitive = true
}

output "public_db_password" {
  value     = random_password.public_db.result
  sensitive = true
}
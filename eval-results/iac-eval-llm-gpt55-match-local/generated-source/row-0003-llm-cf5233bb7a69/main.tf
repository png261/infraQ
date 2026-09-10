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
  alias  = "main"
  region = "us-west-1"
}

provider "aws" {
  alias  = "us-east"
  region = "us-east-1"
}

provider "aws" {
  alias  = "eu-central"
  region = "eu-central-1"
}

provider "aws" {
  alias  = "ap-southeast"
  region = "ap-southeast-1"
}

variable "db_username" {
  type    = string
  default = "adminuser"
}

variable "db_password" {
  type      = string
  default   = "ChangeMe123456789!"
  sensitive = true
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}

data "aws_vpc" "main_default" {
  provider = aws.main
  default  = true
}

data "aws_subnets" "main_default" {
  provider = aws.main

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.main_default.id]
  }
}

data "aws_vpc" "us_east_default" {
  provider = aws.us-east
  default  = true
}

data "aws_subnets" "us_east_default" {
  provider = aws.us-east

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.us_east_default.id]
  }
}

data "aws_vpc" "eu_central_default" {
  provider = aws.eu-central
  default  = true
}

data "aws_subnets" "eu_central_default" {
  provider = aws.eu-central

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.eu_central_default.id]
  }
}

data "aws_vpc" "ap_southeast_default" {
  provider = aws.ap-southeast
  default  = true
}

data "aws_subnets" "ap_southeast_default" {
  provider = aws.ap-southeast

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.ap_southeast_default.id]
  }
}

resource "aws_db_subnet_group" "primary" {
  provider = aws.main

  name       = "primary-db-subnet-group"
  subnet_ids = data.aws_subnets.main_default.ids

  tags = {
    Name = "primary-db-subnet-group"
  }
}

resource "aws_db_subnet_group" "replica_us_east" {
  provider = aws.us-east

  name       = "replica-us-east-db-subnet-group"
  subnet_ids = data.aws_subnets.us_east_default.ids

  tags = {
    Name = "replica-us-east-db-subnet-group"
  }
}

resource "aws_db_subnet_group" "replica_eu_central" {
  provider = aws.eu-central

  name       = "replica-eu-central-db-subnet-group"
  subnet_ids = data.aws_subnets.eu_central_default.ids

  tags = {
    Name = "replica-eu-central-db-subnet-group"
  }
}

resource "aws_db_subnet_group" "replica_ap_southeast" {
  provider = aws.ap-southeast

  name       = "replica-ap-southeast-db-subnet-group"
  subnet_ids = data.aws_subnets.ap_southeast_default.ids

  tags = {
    Name = "replica-ap-southeast-db-subnet-group"
  }
}

resource "aws_security_group" "primary" {
  provider = aws.main

  name        = "primary-db-sg"
  description = "Security group for primary RDS instance"
  vpc_id      = data.aws_vpc.main_default.id

  ingress {
    description = "Allow MySQL access"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.main_default.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "primary-db-sg"
  }
}

resource "aws_security_group" "replica_us_east" {
  provider = aws.us-east

  name        = "replica-us-east-db-sg"
  description = "Security group for us-east-1 RDS replica"
  vpc_id      = data.aws_vpc.us_east_default.id

  ingress {
    description = "Allow MySQL access"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.us_east_default.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "replica-us-east-db-sg"
  }
}

resource "aws_security_group" "replica_eu_central" {
  provider = aws.eu-central

  name        = "replica-eu-central-db-sg"
  description = "Security group for eu-central-1 RDS replica"
  vpc_id      = data.aws_vpc.eu_central_default.id

  ingress {
    description = "Allow MySQL access"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.eu_central_default.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "replica-eu-central-db-sg"
  }
}

resource "aws_security_group" "replica_ap_southeast" {
  provider = aws.ap-southeast

  name        = "replica-ap-southeast-db-sg"
  description = "Security group for ap-southeast-1 RDS replica"
  vpc_id      = data.aws_vpc.ap_southeast_default.id

  ingress {
    description = "Allow MySQL access"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.ap_southeast_default.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "replica-ap-southeast-db-sg"
  }
}

resource "aws_db_instance" "primary" {
  provider = aws.main

  identifier = "primary"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = var.db_instance_class

  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = 100
  storage_type          = "gp3"

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.primary.name
  vpc_security_group_ids = [aws_security_group.primary.id]

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  publicly_accessible = false
  multi_az            = false

  deletion_protection = false
  skip_final_snapshot = true

  apply_immediately = true

  tags = {
    Name = "primary"
  }
}

resource "aws_db_instance" "replica_us_east" {
  provider = aws.us-east

  identifier = "replica-us-east"

  replicate_source_db = aws_db_instance.primary.arn
  instance_class      = var.db_instance_class

  db_subnet_group_name   = aws_db_subnet_group.replica_us_east.name
  vpc_security_group_ids = [aws_security_group.replica_us_east.id]

  publicly_accessible = false
  multi_az            = false

  deletion_protection = false
  skip_final_snapshot = true

  apply_immediately = true

  tags = {
    Name = "replica_us_east"
  }

  depends_on = [
    aws_db_instance.primary
  ]
}

resource "aws_db_instance" "replica_eu_central" {
  provider = aws.eu-central

  identifier = "replica-eu-central"

  replicate_source_db = aws_db_instance.primary.arn
  instance_class      = var.db_instance_class

  db_subnet_group_name   = aws_db_subnet_group.replica_eu_central.name
  vpc_security_group_ids = [aws_security_group.replica_eu_central.id]

  publicly_accessible = false
  multi_az            = false

  deletion_protection = false
  skip_final_snapshot = true

  apply_immediately = true

  tags = {
    Name = "replica_eu_central"
  }

  depends_on = [
    aws_db_instance.primary
  ]
}

resource "aws_db_instance" "replica_ap_southeast" {
  provider = aws.ap-southeast

  identifier = "replica-ap-southeast"

  replicate_source_db = aws_db_instance.primary.arn
  instance_class      = var.db_instance_class

  db_subnet_group_name   = aws_db_subnet_group.replica_ap_southeast.name
  vpc_security_group_ids = [aws_security_group.replica_ap_southeast.id]

  publicly_accessible = false
  multi_az            = false

  deletion_protection = false
  skip_final_snapshot = true

  apply_immediately = true

  tags = {
    Name = "replica_ap_southeast"
  }

  depends_on = [
    aws_db_instance.primary
  ]
}

resource "aws_route53_zone" "main" {
  provider = aws.main

  name = "main"

  comment = "Hosted zone for weighted routing to RDS read replicas"

  tags = {
    Name = "main"
  }
}

resource "aws_route53_record" "replica_us_east" {
  provider = aws.main

  zone_id = aws_route53_zone.main.zone_id
  name    = "db.main"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "replica_us_east"

  weighted_routing_policy {
    weight = 33
  }

  records = [
    aws_db_instance.replica_us_east.address
  ]
}

resource "aws_route53_record" "replica_eu_central" {
  provider = aws.main

  zone_id = aws_route53_zone.main.zone_id
  name    = "db.main"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "replica_eu_central"

  weighted_routing_policy {
    weight = 33
  }

  records = [
    aws_db_instance.replica_eu_central.address
  ]
}

resource "aws_route53_record" "replica_ap_southeast" {
  provider = aws.main

  zone_id = aws_route53_zone.main.zone_id
  name    = "db.main"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "replica_ap_southeast"

  weighted_routing_policy {
    weight = 34
  }

  records = [
    aws_db_instance.replica_ap_southeast.address
  ]
}

output "route53_zone_id" {
  value = aws_route53_zone.main.zone_id
}

output "weighted_db_record" {
  value = aws_route53_record.replica_us_east.fqdn
}

output "primary_db_endpoint" {
  value = aws_db_instance.primary.endpoint
}

output "replica_us_east_endpoint" {
  value = aws_db_instance.replica_us_east.endpoint
}

output "replica_eu_central_endpoint" {
  value = aws_db_instance.replica_eu_central.endpoint
}

output "replica_ap_southeast_endpoint" {
  value = aws_db_instance.replica_ap_southeast.endpoint
}
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

resource "random_id" "suffix" {
  byte_length = 4
}

resource "random_password" "db_password" {
  length  = 20
  special = false
}

resource "aws_route53_zone" "main" {
  provider = aws.main

  name = "main"
}

resource "aws_db_instance" "primary" {
  provider = aws.main

  identifier = "primary-${random_id.suffix.hex}"

  allocated_storage      = 20
  max_allocated_storage  = 100
  storage_type           = "gp2"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = "db.t3.micro"
  db_name                = "maindb"
  username               = "adminuser"
  password               = random_password.db_password.result
  backup_retention_period = 7

  publicly_accessible     = true
  skip_final_snapshot     = true
  deletion_protection     = false
  apply_immediately       = true

  tags = {
    Name = "primary"
  }
}

resource "aws_db_instance" "replica_us_east" {
  provider = aws.us-east

  identifier = "replica-us-east-${random_id.suffix.hex}"

  replicate_source_db = aws_db_instance.primary.arn
  instance_class      = "db.t3.micro"

  publicly_accessible = true
  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true

  tags = {
    Name = "replica_us_east"
  }

  depends_on = [
    aws_db_instance.primary
  ]
}

resource "aws_db_instance" "replica_eu_central" {
  provider = aws.eu-central

  identifier = "replica-eu-central-${random_id.suffix.hex}"

  replicate_source_db = aws_db_instance.primary.arn
  instance_class      = "db.t3.micro"

  publicly_accessible = true
  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true

  tags = {
    Name = "replica_eu_central"
  }

  depends_on = [
    aws_db_instance.primary
  ]
}

resource "aws_db_instance" "replica_ap_southeast" {
  provider = aws.ap-southeast

  identifier = "replica-ap-southeast-${random_id.suffix.hex}"

  replicate_source_db = aws_db_instance.primary.arn
  instance_class      = "db.t3.micro"

  publicly_accessible = true
  skip_final_snapshot = true
  deletion_protection = false
  apply_immediately   = true

  tags = {
    Name = "replica_ap_southeast"
  }

  depends_on = [
    aws_db_instance.primary
  ]
}

resource "aws_route53_record" "replica_us_east_weighted" {
  provider = aws.main

  zone_id = aws_route53_zone.main.zone_id
  name    = "db.main"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "replica_us_east"

  weighted_routing_policy {
    weight = 100
  }

  records = [
    aws_db_instance.replica_us_east.address
  ]
}

resource "aws_route53_record" "replica_eu_central_weighted" {
  provider = aws.main

  zone_id = aws_route53_zone.main.zone_id
  name    = "db.main"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "replica_eu_central"

  weighted_routing_policy {
    weight = 100
  }

  records = [
    aws_db_instance.replica_eu_central.address
  ]
}

resource "aws_route53_record" "replica_ap_southeast_weighted" {
  provider = aws.main

  zone_id = aws_route53_zone.main.zone_id
  name    = "db.main"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "replica_ap_southeast"

  weighted_routing_policy {
    weight = 100
  }

  records = [
    aws_db_instance.replica_ap_southeast.address
  ]
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

output "weighted_database_dns_name" {
  value = "db.${aws_route53_zone.main.name}"
}
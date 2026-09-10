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
  region = "us-west-2"
}

resource "random_password" "db_password" {
  length  = 20
  special = false
}

resource "aws_db_instance" "primary" {
  identifier = "primary"

  engine         = "mysql"
  engine_version = "8.0"
  instance_class = "db.t3.micro"

  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "maindb"
  username = "adminuser"
  password = random_password.db_password.result

  backup_retention_period = 1

  publicly_accessible = true

  skip_final_snapshot = true
  deletion_protection = false

  tags = {
    Name = "primary"
  }
}

resource "aws_db_instance" "replica_1" {
  identifier = "replica-1"

  replicate_source_db = aws_db_instance.primary.identifier
  instance_class      = "db.t3.micro"

  publicly_accessible = true

  skip_final_snapshot = true
  deletion_protection = false

  tags = {
    Name = "replica-1"
  }
}

resource "aws_db_instance" "replica_2" {
  identifier = "replica-2"

  replicate_source_db = aws_db_instance.primary.identifier
  instance_class      = "db.t3.micro"

  publicly_accessible = true

  skip_final_snapshot = true
  deletion_protection = false

  tags = {
    Name = "replica-2"
  }
}

resource "aws_route53_zone" "main" {
  name = "main"
}

resource "aws_route53_record" "replica_1_weighted" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "db.main"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "replica-1"

  weighted_routing_policy {
    weight = 50
  }

  records = [
    aws_db_instance.replica_1.address
  ]
}

resource "aws_route53_record" "replica_2_weighted" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "db.main"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "replica-2"

  weighted_routing_policy {
    weight = 50
  }

  records = [
    aws_db_instance.replica_2.address
  ]
}

output "primary_endpoint" {
  value = aws_db_instance.primary.endpoint
}

output "replica_1_endpoint" {
  value = aws_db_instance.replica_1.endpoint
}

output "replica_2_endpoint" {
  value = aws_db_instance.replica_2.endpoint
}

output "weighted_database_dns_name" {
  value = aws_route53_record.replica_1_weighted.fqdn
}
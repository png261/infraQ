resource "aws_route53_zone" "main" {
  provider = aws.main

  name = "main"
}

resource "aws_db_instance" "primary" {
  provider = aws.main

  identifier              = "master"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  engine                  = "mysql"
  username                = var.db_username
  password                = var.db_password
  backup_retention_period = 1
  skip_final_snapshot     = true
}

resource "aws_db_instance" "replica_us_east" {
  provider = aws.us-east

  # AWS RDS instance identifiers allow hyphens, not underscores; the Terraform
  # resource name preserves the requested benchmark name: replica_us_east.
  identifier          = "replica-us-east"
  instance_class      = "db.t3.micro"
  replicate_source_db = aws_db_instance.primary.arn
}

resource "aws_db_instance" "replica_eu_central" {
  provider = aws.eu-central

  # AWS RDS instance identifiers allow hyphens, not underscores; the Terraform
  # resource name preserves the requested benchmark name: replica_eu_central.
  identifier          = "replica-eu-central"
  instance_class      = "db.t3.micro"
  replicate_source_db = aws_db_instance.primary.arn
}

resource "aws_db_instance" "replica_ap_southeast" {
  provider = aws.ap-southeast

  # AWS RDS instance identifiers allow hyphens, not underscores; the Terraform
  # resource name preserves the requested benchmark name: replica_ap_southeast.
  identifier          = "replica-ap-southeast"
  instance_class      = "db.t3.micro"
  replicate_source_db = aws_db_instance.primary.arn
}

resource "aws_route53_record" "replica_us_east" {
  provider = aws.main

  zone_id = aws_route53_zone.main.zone_id
  name    = "db.main"
  type    = "CNAME"
  ttl     = 60
  records = [aws_db_instance.replica_us_east.address]

  weighted_routing_policy {
    weight = 100
  }

  set_identifier = "replica_us_east"
}

resource "aws_route53_record" "replica_eu_central" {
  provider = aws.main

  zone_id = aws_route53_zone.main.zone_id
  name    = "db.main"
  type    = "CNAME"
  ttl     = 60
  records = [aws_db_instance.replica_eu_central.address]

  weighted_routing_policy {
    weight = 100
  }

  set_identifier = "replica_eu_central"
}

resource "aws_route53_record" "replica_ap_southeast" {
  provider = aws.main

  zone_id = aws_route53_zone.main.zone_id
  name    = "db.main"
  type    = "CNAME"
  ttl     = 60
  records = [aws_db_instance.replica_ap_southeast.address]

  weighted_routing_policy {
    weight = 100
  }

  set_identifier = "replica_ap_southeast"
}

resource "aws_route53_zone" "main" {
  name = "main"
}

resource "aws_db_instance" "primary" {
  identifier              = "primary"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  engine                  = "mysql"
  username                = "adminuser"
  password                = "ChangeMe123!"
  backup_retention_period = 1
  skip_final_snapshot     = true
}

resource "aws_db_instance" "replica-1" {
  identifier          = "replica-1"
  replicate_source_db = aws_db_instance.primary.identifier
  instance_class      = "db.t3.micro"
  skip_final_snapshot = true
}

resource "aws_db_instance" "replica-2" {
  identifier          = "replica-2"
  replicate_source_db = aws_db_instance.primary.identifier
  instance_class      = "db.t3.micro"
  skip_final_snapshot = true
}

resource "aws_route53_record" "replica_1" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "db.main"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "replica-1"

  weighted_routing_policy {
    weight = 50
  }

  records = [aws_db_instance.replica-1.address]
}

resource "aws_route53_record" "replica_2" {
  zone_id = aws_route53_zone.main.zone_id
  name    = "db.main"
  type    = "CNAME"
  ttl     = 60

  set_identifier = "replica-2"

  weighted_routing_policy {
    weight = 50
  }

  records = [aws_db_instance.replica-2.address]
}

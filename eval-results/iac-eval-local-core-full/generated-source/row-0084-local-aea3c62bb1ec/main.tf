resource "aws_route53_zone" "primary" {
  name = "primary.example.com"
}

resource "aws_route53_record" "primary_us_east_1" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "app.primary.example.com"
  type    = "A"
  ttl     = 60
  records = ["192.0.2.10"]

  set_identifier = "primary-us-east-1"

  latency_routing_policy {
    region = "us-east-1"
  }
}

resource "aws_route53_record" "primary_eu_central_1" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "app.primary.example.com"
  type    = "A"
  ttl     = 60
  records = ["192.0.2.20"]

  set_identifier = "primary-eu-central-1"

  latency_routing_policy {
    region = "eu-central-1"
  }
}

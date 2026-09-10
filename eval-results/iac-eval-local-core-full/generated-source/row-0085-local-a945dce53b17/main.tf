resource "aws_route53_zone" "primary" {
  name = "primary.example.com"
}

resource "aws_route53_record" "primary_na" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "app.${aws_route53_zone.primary.name}"
  type    = "A"
  ttl     = 300
  records = ["192.0.2.10"]

  set_identifier = "north-america"

  geolocation_routing_policy {
    continent = "NA"
  }
}

resource "aws_route53_record" "primary_eu" {
  zone_id = aws_route53_zone.primary.zone_id
  name    = "app.${aws_route53_zone.primary.name}"
  type    = "A"
  ttl     = 300
  records = ["198.51.100.10"]

  set_identifier = "europe"

  geolocation_routing_policy {
    continent = "EU"
  }
}

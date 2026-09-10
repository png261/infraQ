resource "aws_route53_zone" "main" {
  name = "example.com"
}

resource "aws_route53_health_check" "primary_health_check" {
  fqdn              = "primary.example.com"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/"
  request_interval  = 30
  failure_threshold = 3
}

resource "aws_route53_health_check" "secondary_health_check" {
  fqdn              = "secondary.example.com"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/"
  request_interval  = 30
  failure_threshold = 3
}

resource "aws_route53_record" "primary" {
  zone_id         = aws_route53_zone.main.zone_id
  name            = "app.example.com"
  type            = "A"
  ttl             = 60
  records         = ["192.0.2.10"]
  health_check_id = aws_route53_health_check.primary_health_check.id
  set_identifier  = "primary"

  failover_routing_policy {
    type = "PRIMARY"
  }
}

resource "aws_route53_record" "secondary" {
  zone_id         = aws_route53_zone.main.zone_id
  name            = "app.example.com"
  type            = "A"
  ttl             = 60
  records         = ["192.0.2.20"]
  health_check_id = aws_route53_health_check.secondary_health_check.id
  set_identifier  = "secondary"

  failover_routing_policy {
    type = "SECONDARY"
  }
}

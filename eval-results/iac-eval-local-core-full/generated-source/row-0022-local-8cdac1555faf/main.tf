resource "aws_route53_zone" "reverse_zone" {
  name = "2.0.192.in-addr.arpa"
}

resource "aws_route53_record" "host_ptr" {
  zone_id = aws_route53_zone.reverse_zone.zone_id
  name    = "1.2.0.192.in-addr.arpa"
  type    = "PTR"
  ttl     = 300
  records = ["host.example53.com"]
}

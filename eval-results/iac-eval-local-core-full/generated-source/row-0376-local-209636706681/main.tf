resource "aws_lightsail_certificate" "this" {
  name        = "example-lightsail-certificate"
  domain_name = "example.com"
}

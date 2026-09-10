resource "aws_lightsail_instance" "default" {
  name              = "iac-eval-lightsail-instance"
  availability_zone = "us-east-1a"
  blueprint_id      = "amazon_linux_2"
  bundle_id         = "nano_3_0"
}

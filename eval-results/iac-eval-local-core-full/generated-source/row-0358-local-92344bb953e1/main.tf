resource "aws_lightsail_instance" "basic" {
  name              = "basic-lightsail-instance"
  availability_zone = "us-east-1a"
  blueprint_id      = "amazon_linux_2023"
  bundle_id         = "nano_3_0"
}

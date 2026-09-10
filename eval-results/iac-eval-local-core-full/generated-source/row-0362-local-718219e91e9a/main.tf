resource "aws_lightsail_instance" "wordpress" {
  name              = "wordpress-lightsail"
  availability_zone = "us-east-1a"
  blueprint_id      = "wordpress"
  bundle_id         = "nano_3_0"
}

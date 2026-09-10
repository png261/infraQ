provider "aws" {
  region = "us-east-1"
}

resource "aws_lightsail_instance" "dualstack" {
  name              = "benchmark-dualstack-lightsail"
  availability_zone = "us-east-1a"
  blueprint_id      = "amazon_linux_2"
  bundle_id         = "nano_3_0"
  ip_address_type   = "dualstack"
}

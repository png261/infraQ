resource "aws_lightsail_bucket" "example" {
  name      = "iac-eval-lightsail-bucket"
  bundle_id = "small_1_0"
}

resource "aws_lightsail_instance" "example" {
  name              = "iac-eval-lightsail-instance"
  availability_zone = "us-east-1a"
  blueprint_id      = "amazon_linux_2"
  bundle_id         = "nano_3_0"
}

resource "aws_lightsail_bucket_resource_access" "example" {
  bucket_name   = aws_lightsail_bucket.example.name
  resource_name = aws_lightsail_instance.example.name
}

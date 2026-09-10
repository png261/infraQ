resource "aws_lightsail_instance" "basic" {
  name              = "basic-lightsail-instance"
  availability_zone = "us-east-1a"
  blueprint_id      = "amazon_linux_2"
  bundle_id         = "nano_3_0"

  user_data = <<-EOT
    #!/bin/bash
    echo "Hello from Terraform-managed Lightsail" > /home/ec2-user/hello.txt
  EOT
}

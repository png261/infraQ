data "aws_ami" "latest_amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }
}

resource "aws_ami" "latest_amazon_linux_2" {
  name                = "latest-amazon-linux-2-benchmark"
  virtualization_type = data.aws_ami.latest_amazon_linux_2.virtualization_type
  root_device_name    = data.aws_ami.latest_amazon_linux_2.root_device_name

  ebs_block_device {
    device_name = data.aws_ami.latest_amazon_linux_2.root_device_name
    snapshot_id = data.aws_ami.latest_amazon_linux_2.root_snapshot_id
  }
}

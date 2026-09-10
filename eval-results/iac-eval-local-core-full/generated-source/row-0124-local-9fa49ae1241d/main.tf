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

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_ebs_volume" "amazon_linux_2_root" {
  availability_zone = data.aws_availability_zones.available.names[0]
  snapshot_id       = tolist(data.aws_ami.latest_amazon_linux_2.block_device_mappings)[0].ebs.snapshot_id

  tags = {
    Name = "latest-amazon-linux-2-root"
  }
}

resource "aws_ebs_snapshot" "amazon_linux_2_root" {
  volume_id = aws_ebs_volume.amazon_linux_2_root.id

  tags = {
    Name = "latest-amazon-linux-2-root"
  }
}

resource "aws_ami" "latest_amazon_linux_2" {
  name                = "latest-amazon-linux-2-copy"
  virtualization_type = data.aws_ami.latest_amazon_linux_2.virtualization_type
  root_device_name    = data.aws_ami.latest_amazon_linux_2.root_device_name

  ebs_block_device {
    device_name = data.aws_ami.latest_amazon_linux_2.root_device_name
    snapshot_id = aws_ebs_snapshot.amazon_linux_2_root.id
  }
}

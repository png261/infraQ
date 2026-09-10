data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "amazon_linux_2_source" {
  ami           = data.aws_ami.amazon_linux_2.id
  instance_type = "c5.xlarge"

  tags = {
    Name = "amazon-linux-2-ami-source"
  }
}

resource "aws_ami" "amazon_linux_2_custom" {
  name                = "amazon-linux-2-custom-cpu-options"
  architecture        = data.aws_ami.amazon_linux_2.architecture
  root_device_name    = data.aws_ami.amazon_linux_2.root_device_name
  virtualization_type = data.aws_ami.amazon_linux_2.virtualization_type

  cpu_options {
    core_count       = 2
    threads_per_core = 2
  }

  ebs_block_device {
    device_name           = data.aws_ami.amazon_linux_2.root_device_name
    snapshot_id           = tolist(data.aws_ami.amazon_linux_2.block_device_mappings)[0].ebs.snapshot_id
    volume_size           = tolist(data.aws_ami.amazon_linux_2.block_device_mappings)[0].ebs.volume_size
    volume_type           = tolist(data.aws_ami.amazon_linux_2.block_device_mappings)[0].ebs.volume_type
    delete_on_termination = true
  }

  tags = {
    Name = "amazon-linux-2-custom-cpu-options"
  }
}

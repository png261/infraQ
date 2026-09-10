data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_lightsail_instance" "compute" {
  name              = "benchmark-lightsail-instance"
  availability_zone = data.aws_availability_zones.available.names[0]
  blueprint_id      = "amazon_linux_2"
  bundle_id         = "nano_3_0"
}

resource "aws_lightsail_disk" "storage" {
  name              = "benchmark-lightsail-disk"
  size_in_gb        = 8
  availability_zone = data.aws_availability_zones.available.names[0]
}

resource "aws_lightsail_disk_attachment" "storage" {
  disk_name     = aws_lightsail_disk.storage.name
  instance_name = aws_lightsail_instance.compute.name
  disk_path     = "/dev/xvdf"
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  availability_zone = data.aws_availability_zones.available.names[0]

  lightsail_disks = {
    data = {
      name       = "benchmark-lightsail-data-disk"
      size_in_gb = 8
      disk_path  = "/dev/xvdf"
    }
    logs = {
      name       = "benchmark-lightsail-logs-disk"
      size_in_gb = 8
      disk_path  = "/dev/xvdg"
    }
  }
}

resource "aws_lightsail_instance" "benchmark" {
  name              = "benchmark-lightsail-instance"
  availability_zone = local.availability_zone
  blueprint_id      = "amazon_linux_2"
  bundle_id         = "nano_3_0"
}

resource "aws_lightsail_disk" "benchmark" {
  for_each = local.lightsail_disks

  name              = each.value.name
  size_in_gb        = each.value.size_in_gb
  availability_zone = local.availability_zone
}

resource "aws_lightsail_disk_attachment" "benchmark" {
  for_each = aws_lightsail_disk.benchmark

  disk_name     = each.value.name
  instance_name = aws_lightsail_instance.benchmark.name
  disk_path     = local.lightsail_disks[each.key].disk_path
}

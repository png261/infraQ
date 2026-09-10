resource "aws_vpc" "efs" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "benchmark-efs-vpc"
  }
}

resource "aws_subnet" "efs" {
  vpc_id            = aws_vpc.efs.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "benchmark-efs-subnet"
  }
}

resource "aws_efs_file_system" "this" {
  encrypted = true

  tags = {
    Name = "benchmark-efs"
  }
}

resource "aws_efs_mount_target" "this" {
  file_system_id = aws_efs_file_system.this.id
  subnet_id      = aws_subnet.efs.id
}

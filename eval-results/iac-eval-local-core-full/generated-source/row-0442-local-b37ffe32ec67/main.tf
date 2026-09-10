resource "aws_vpc" "specified" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "pike-vpc"
  }
}

resource "aws_vpc_dhcp_options" "pike" {
  domain_name_servers = ["8.8.8.8", "8.8.4.4"]

  tags = {
    Name        = "pike"
    permissions = "true"
  }
}

resource "aws_vpc_dhcp_options_association" "pike" {
  vpc_id          = aws_vpc.specified.id
  dhcp_options_id = aws_vpc_dhcp_options.pike.id
}

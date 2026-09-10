resource "aws_vpc" "pike" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "pike"
  }
}

resource "aws_vpc_dhcp_options" "pike" {
  domain_name_servers = ["8.8.8.8", "8.8.4.4"]

  tags = {
    Name        = "pike"
    permissions = "pike"
  }
}

resource "aws_vpc_dhcp_options_association" "pike" {
  vpc_id          = aws_vpc.pike.id
  dhcp_options_id = aws_vpc_dhcp_options.pike.id
}

resource "aws_vpc" "pike" {
  cidr_block                       = "10.0.0.0/16"
  assign_generated_ipv6_cidr_block = true

  tags = {
    Name = "pike"
  }
}

resource "aws_egress_only_internet_gateway" "pike" {
  vpc_id = aws_vpc.pike.id

  tags = {
    Name        = "pike"
    permissions = "egress-only-ipv6"
  }
}

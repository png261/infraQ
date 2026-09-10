resource "aws_vpc" "this" {
  cidr_block                       = var.vpc_cidr_block
  assign_generated_ipv6_cidr_block = true

  tags = {
    Name = var.name
  }
}

resource "aws_egress_only_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name = var.name
  }
}

resource "aws_route_table" "ipv6_egress" {
  vpc_id = aws_vpc.this.id

  route {
    ipv6_cidr_block        = "::/0"
    egress_only_gateway_id = aws_egress_only_internet_gateway.this.id
  }

  tags = {
    Name = "${var.name}-ipv6-egress"
  }
}

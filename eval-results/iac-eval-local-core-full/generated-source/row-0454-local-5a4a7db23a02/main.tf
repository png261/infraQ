resource "aws_vpc" "peer" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "peer"
  }
}

resource "aws_vpc" "base" {
  cidr_block = "10.1.0.0/16"

  tags = {
    Name = "base"
  }
}

resource "aws_vpc_peering_connection" "pike" {
  vpc_id      = aws_vpc.peer.id
  peer_vpc_id = aws_vpc.base.id
  auto_accept = true

  tags = {
    Name = "pike"
    pike = "permissions"
  }
}

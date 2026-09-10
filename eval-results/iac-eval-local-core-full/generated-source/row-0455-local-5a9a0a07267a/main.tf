resource "aws_vpc" "benchmark" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "iac-eval-default-nacl-benchmark"
  }
}

resource "aws_default_network_acl" "benchmark" {
  default_network_acl_id = aws_vpc.benchmark.default_network_acl_id

  ingress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = "-1"
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = {
    Name = "iac-eval-default-nacl-benchmark"
  }
}

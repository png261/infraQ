resource "aws_vpc" "chapter4_demo" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "chapter4-drift-demo-${var.test_id}"
    Experiment  = "chapter4-drift-remediation"
    ManagedBy   = "terraform"
    ThesisScope = "drift-detection-auto-remediation"
  }
}

resource "aws_security_group" "chapter4_demo" {
  name        = "chapter4-drift-demo-${var.test_id}"
  description = "Chapter 4 drift demo: expected no inbound SSH from the internet"
  vpc_id      = aws_vpc.chapter4_demo.id

  ingress = []

  egress {
    description = "Allow outbound HTTPS for normal managed baseline"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "chapter4-drift-demo-${var.test_id}"
    Experiment  = "chapter4-drift-remediation"
    ManagedBy   = "terraform"
    ThesisScope = "drift-detection-auto-remediation"
  }
}

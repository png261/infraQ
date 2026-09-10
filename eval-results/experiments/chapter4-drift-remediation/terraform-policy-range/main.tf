resource "aws_vpc" "chapter4_demo" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "chapter4-policy-range-${var.test_id}"
    Experiment  = "chapter4-policy-detection"
    ManagedBy   = "terraform"
    ThesisScope = "policy-detection-auto-remediation"
  }
}

# CH4-POLICY-SG-RANGE-018: Terraform declares tcp/20-25 from 0.0.0.0/0.
# Port 22 falls within this range, triggering CKV_AWS_25 policy violation.
# No drift: actual state matches Terraform state.
resource "aws_security_group" "chapter4_demo" {
  name        = "chapter4-policy-range-${var.test_id}"
  description = "Chapter 4 policy range demo: Terraform-authored public tcp/20-25 ingress"
  vpc_id      = aws_vpc.chapter4_demo.id

  ingress {
    description = "Unsafe public port range including SSH - intentional for policy detection test"
    from_port   = 20
    to_port     = 25
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "chapter4-policy-range-${var.test_id}"
    Experiment  = "chapter4-policy-detection"
    ManagedBy   = "terraform"
    ThesisScope = "policy-detection-auto-remediation"
  }
}

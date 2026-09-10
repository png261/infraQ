resource "aws_vpc" "chapter4_demo" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "chapter4-policy-demo-${var.test_id}"
    Experiment  = "chapter4-policy-detection"
    ManagedBy   = "terraform"
    ThesisScope = "policy-detection-auto-remediation"
  }
}

# CH4-POLICY-SG-SSH-017: Terraform itself declares the unsafe public SSH ingress.
# There is no drift (actual state matches Terraform state), but Cloudrift detects
# a policy violation: CKV_AWS_25 (security group allows SSH from 0.0.0.0/0).
resource "aws_security_group" "chapter4_demo" {
  name        = "chapter4-policy-demo-${var.test_id}"
  description = "Chapter 4 policy demo: Terraform-authored public SSH ingress"
  vpc_id      = aws_vpc.chapter4_demo.id

  ingress {
    description = "Unsafe public SSH - intentional for policy detection test"
    from_port   = 22
    to_port     = 22
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
    Name        = "chapter4-policy-demo-${var.test_id}"
    Experiment  = "chapter4-policy-detection"
    ManagedBy   = "terraform"
    ThesisScope = "policy-detection-auto-remediation"
  }
}

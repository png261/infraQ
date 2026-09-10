data "aws_availability_zones" "available" {
  provider = aws.aws
  state    = "available"
}

resource "aws_vpc" "msk" {
  provider             = aws.aws
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "benchmark-msk-serverless-vpc"
  }
}

resource "aws_subnet" "msk_a" {
  provider          = aws.aws
  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.0.0.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "benchmark-msk-serverless-a"
  }
}

resource "aws_subnet" "msk_b" {
  provider          = aws.aws
  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "benchmark-msk-serverless-b"
  }
}

resource "aws_subnet" "msk_c" {
  provider          = aws.aws
  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[2]

  tags = {
    Name = "benchmark-msk-serverless-c"
  }
}

resource "aws_security_group" "msk" {
  provider    = aws.aws
  name        = "benchmark-msk-serverless-sg"
  description = "Security group for the benchmark MSK Serverless cluster"
  vpc_id      = aws_vpc.msk.id

  egress {
    description = "Allow outbound HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "benchmark-msk-serverless-sg"
  }
}

resource "aws_msk_serverless_cluster" "benchmark" {
  provider     = aws.aws
  cluster_name = "benchmark-msk-serverless"

  vpc_config {
    subnet_ids         = [aws_subnet.msk_a.id, aws_subnet.msk_b.id, aws_subnet.msk_c.id]
    security_group_ids = [aws_security_group.msk.id]
  }

  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }
}

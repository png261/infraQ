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
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "benchmark-msk-serverless-subnet-a"
  }
}

resource "aws_subnet" "msk_b" {
  provider          = aws.aws
  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "benchmark-msk-serverless-subnet-b"
  }
}

resource "aws_subnet" "msk_c" {
  provider          = aws.aws
  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = data.aws_availability_zones.available.names[2]

  tags = {
    Name = "benchmark-msk-serverless-subnet-c"
  }
}

resource "aws_security_group" "msk" {
  provider    = aws.aws
  name        = "benchmark-msk-serverless-sg"
  description = "Security group for benchmark MSK Serverless cluster"
  vpc_id      = aws_vpc.msk.id

  ingress {
    description = "Kafka TLS from within VPC"
    from_port   = 9098
    to_port     = 9098
    protocol    = "tcp"
    cidr_blocks = [aws_vpc.msk.cidr_block]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "benchmark-msk-serverless-sg"
  }
}

resource "aws_msk_serverless_cluster" "this" {
  provider     = aws.aws
  cluster_name = "benchmark-msk-serverless"

  vpc_config {
    subnet_ids = [
      aws_subnet.msk_a.id,
      aws_subnet.msk_b.id,
      aws_subnet.msk_c.id,
    ]
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

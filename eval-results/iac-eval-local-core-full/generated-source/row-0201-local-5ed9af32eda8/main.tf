data "aws_availability_zones" "available" {
  provider = aws.aws
  state    = "available"
}

resource "aws_vpc" "msk" {
  provider = aws.aws

  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "benchmark-msk-vpc"
  }
}

resource "aws_subnet" "broker_a" {
  provider = aws.aws

  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = {
    Name = "benchmark-msk-broker-a"
  }
}

resource "aws_subnet" "broker_b" {
  provider = aws.aws

  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = data.aws_availability_zones.available.names[1]

  tags = {
    Name = "benchmark-msk-broker-b"
  }
}

resource "aws_subnet" "broker_c" {
  provider = aws.aws

  vpc_id            = aws_vpc.msk.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = data.aws_availability_zones.available.names[2]

  tags = {
    Name = "benchmark-msk-broker-c"
  }
}

resource "aws_security_group" "msk" {
  provider = aws.aws

  name        = "benchmark-msk-sg"
  description = "Security group for benchmark MSK cluster"
  vpc_id      = aws_vpc.msk.id

  ingress {
    description = "Allow Kafka TLS within the VPC"
    from_port   = 9094
    to_port     = 9094
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
    Name = "benchmark-msk-sg"
  }
}

resource "aws_msk_cluster" "benchmark" {
  provider = aws.aws

  cluster_name           = "benchmark-msk-cluster"
  kafka_version          = "3.5.1"
  number_of_broker_nodes = 3

  broker_node_group_info {
    instance_type   = "kafka.t3.small"
    client_subnets  = [aws_subnet.broker_a.id, aws_subnet.broker_b.id, aws_subnet.broker_c.id]
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = 100
      }
    }
  }

  encryption_info {
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  tags = {
    Name = "benchmark-msk-cluster"
  }
}

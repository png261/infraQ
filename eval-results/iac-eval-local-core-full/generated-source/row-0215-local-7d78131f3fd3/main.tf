data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  az_names = slice(data.aws_availability_zones.available.names, 0, 2)
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = var.name
  }
}

resource "aws_subnet" "database" {
  for_each = {
    for index, az_name in local.az_names : az_name => index
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, each.value)
  availability_zone = each.key

  tags = {
    Name = "${var.name}-db-${each.key}"
  }
}

resource "aws_db_subnet_group" "database" {
  name       = var.name
  subnet_ids = [for subnet in aws_subnet.database : subnet.id]

  tags = {
    Name = var.name
  }
}

resource "aws_security_group" "database" {
  name        = "${var.name}-db"
  description = "Security group for the Aurora MySQL cluster"
  vpc_id      = aws_vpc.main.id

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.name}-db"
  }
}

resource "aws_rds_cluster" "aurora_mysql" {
  cluster_identifier     = var.name
  engine                 = "aurora-mysql"
  engine_version         = "8.0.mysql_aurora.3.05.2"
  database_name          = "appdb"
  master_username        = var.db_master_username
  manage_master_user_password = true
  db_subnet_group_name   = aws_db_subnet_group.database.name
  vpc_security_group_ids = [aws_security_group.database.id]
  skip_final_snapshot    = true

  tags = {
    Name = var.name
  }
}

resource "aws_rds_cluster_instance" "aurora_mysql" {
  identifier         = "${var.name}-1"
  cluster_identifier = aws_rds_cluster.aurora_mysql.id
  instance_class     = "db.t3.medium"
  engine             = aws_rds_cluster.aurora_mysql.engine
  engine_version     = aws_rds_cluster.aurora_mysql.engine_version
}

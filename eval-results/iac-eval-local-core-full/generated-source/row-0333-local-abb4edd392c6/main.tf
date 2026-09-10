data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "db_a" {
  vpc_id                  = var.vpc_id
  cidr_block              = var.private_subnet_cidr_blocks[0]
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "postgres-db-subnet-a"
  }
}

resource "aws_subnet" "db_b" {
  vpc_id                  = var.vpc_id
  cidr_block              = var.private_subnet_cidr_blocks[1]
  availability_zone       = data.aws_availability_zones.available.names[1]
  map_public_ip_on_launch = false

  tags = {
    Name = "postgres-db-subnet-b"
  }
}

resource "aws_security_group" "postgres" {
  name        = "secure-postgres-rds"
  description = "Controls access to the PostgreSQL RDS instance"
  vpc_id      = var.vpc_id

  ingress {
    description = "PostgreSQL access from approved CIDR blocks"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = var.db_ingress_cidr_blocks
  }

  egress {
    description = "Allow outbound traffic from RDS"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "secure-postgres-rds"
  }
}

resource "aws_db_subnet_group" "postgres" {
  name       = "secure-postgres-subnet-group"
  subnet_ids = [aws_subnet.db_a.id, aws_subnet.db_b.id]

  tags = {
    Name = "secure-postgres-subnet-group"
  }
}

resource "aws_db_parameter_group" "postgres" {
  name        = "secure-postgres-parameter-group"
  family      = "postgres15"
  description = "Custom PostgreSQL parameters requiring encrypted passwords and SSL"

  parameter {
    name  = "password_encryption"
    value = "scram-sha-256"
  }

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }
}

resource "aws_kms_key" "postgres" {
  description             = "KMS key for encrypting PostgreSQL RDS storage"
  deletion_window_in_days = 7
  enable_key_rotation     = true
}

resource "aws_db_instance" "postgres" {
  identifier             = "secure-postgres-db"
  allocated_storage      = 200
  engine                 = "postgres"
  engine_version         = "15.8"
  instance_class         = "db.t3.micro"
  username               = var.db_username
  password               = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.postgres.name
  parameter_group_name   = aws_db_parameter_group.postgres.name
  vpc_security_group_ids = [aws_security_group.postgres.id]

  multi_az                  = true
  storage_encrypted        = true
  kms_key_id               = aws_kms_key.postgres.arn
  publicly_accessible      = false
  final_snapshot_identifier = "pgsnapshot"
  skip_final_snapshot       = false

  backup_retention_period = 7
  deletion_protection     = true
}

resource "random_string" "db_password" {
  length  = 16
  special = false
}

resource "aws_security_group" "rds_public" {
  name        = "benchmark-rds-public-sg"
  description = "Public access security group for benchmark MySQL RDS instance"

  ingress {
    description = "Allow public MySQL access for benchmark task"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "mysql" {
  allocated_storage      = 20
  engine                 = "mysql"
  instance_class         = "db.t3.micro"
  db_name                = "benchmarkdb"
  username               = "adminuser"
  password               = random_string.db_password.result
  publicly_accessible    = true
  vpc_security_group_ids = [aws_security_group.rds_public.id]
  skip_final_snapshot    = true
}

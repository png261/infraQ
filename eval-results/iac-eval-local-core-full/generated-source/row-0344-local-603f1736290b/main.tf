resource "random_string" "db_password" {
  length  = 16
  special = false
}

resource "aws_security_group" "public_rds" {
  name        = "iac-eval-public-rds-mysql"
  description = "Public access security group for MySQL RDS benchmark"

  ingress {
    description = "Allow public MySQL access"
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
  identifier             = "iac-eval-mysql-57"
  allocated_storage      = 200
  engine                 = "mysql"
  engine_version         = "5.7"
  instance_class         = "db.t3.micro"
  username               = "adminuser"
  password               = random_string.db_password.result
  publicly_accessible    = true
  vpc_security_group_ids = [aws_security_group.public_rds.id]
  skip_final_snapshot    = true
}

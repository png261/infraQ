data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_iam_policy_document" "rds_proxy_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

data "aws_iam_policy_document" "rds_proxy_secrets" {
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]

    resources = [aws_secretsmanager_secret.db_credentials.arn]
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project_name}-vpc"
  }
}

resource "aws_subnet" "database" {
  count = 2

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.subnet_cidr_blocks[count.index]
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name = "${var.project_name}-db-${count.index + 1}"
  }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-rds-sg"
  description = "Allow MySQL access to Aurora from the RDS proxy."
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-rds-sg"
  }
}

resource "aws_security_group" "proxy" {
  name        = "${var.project_name}-proxy-sg"
  description = "Allow application traffic to the RDS proxy and proxy traffic to Aurora."
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-proxy-sg"
  }
}

resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "Example EC2/application security group allowed to connect to the RDS proxy."
  vpc_id      = aws_vpc.main.id

  tags = {
    Name = "${var.project_name}-ec2-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "proxy_from_ec2_mysql" {
  description                  = "MySQL from EC2/application security group to RDS proxy"
  security_group_id            = aws_security_group.proxy.id
  referenced_security_group_id = aws_security_group.ec2.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "ec2_to_proxy_mysql" {
  description                  = "MySQL from EC2/application security group to RDS proxy"
  security_group_id            = aws_security_group.ec2.id
  referenced_security_group_id = aws_security_group.proxy.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_proxy_mysql" {
  description                  = "MySQL from RDS proxy security group to Aurora"
  security_group_id            = aws_security_group.rds.id
  referenced_security_group_id = aws_security_group.proxy.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "proxy_to_rds_mysql" {
  description                  = "MySQL from RDS proxy security group to Aurora"
  security_group_id            = aws_security_group.proxy.id
  referenced_security_group_id = aws_security_group.rds.id
  from_port                    = 3306
  to_port                      = 3306
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "rds_all_outbound" {
  description       = "Allow outbound traffic from Aurora as needed"
  security_group_id = aws_security_group.rds.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

resource "aws_db_subnet_group" "database" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = aws_subnet.database[*].id

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name        = "${var.project_name}-db-credentials"
  description = "Aurora MySQL credentials for the RDS proxy."
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_master_username
    password = var.db_master_password
  })
}

resource "aws_iam_role" "rds_proxy" {
  name               = "${var.project_name}-rds-proxy-role"
  assume_role_policy = data.aws_iam_policy_document.rds_proxy_assume_role.json
}

resource "aws_iam_role_policy" "rds_proxy_secrets" {
  name   = "${var.project_name}-rds-proxy-secrets"
  role   = aws_iam_role.rds_proxy.id
  policy = data.aws_iam_policy_document.rds_proxy_secrets.json
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier      = "${var.project_name}-cluster"
  engine                  = "aurora-mysql"
  database_name           = var.db_name
  master_username         = var.db_master_username
  master_password         = var.db_master_password
  db_subnet_group_name    = aws_db_subnet_group.database.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  backup_retention_period = 5
  preferred_backup_window = "07:00-09:00"
  skip_final_snapshot     = true
}

resource "aws_rds_cluster_instance" "aurora" {
  identifier         = "${var.project_name}-instance-1"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = var.db_instance_class
  engine             = aws_rds_cluster.aurora.engine
}

resource "aws_db_proxy" "aurora" {
  name                   = "${var.project_name}-proxy"
  debug_logging          = false
  engine_family          = "MYSQL"
  idle_client_timeout    = 1800
  require_tls            = true
  role_arn               = aws_iam_role.rds_proxy.arn
  vpc_security_group_ids = [aws_security_group.proxy.id]
  vpc_subnet_ids         = aws_subnet.database[*].id

  auth {
    auth_scheme = "SECRETS"
    description = "Secrets Manager authentication for Aurora MySQL"
    iam_auth    = "DISABLED"
    secret_arn  = aws_secretsmanager_secret.db_credentials.arn
  }
}

resource "aws_db_proxy_default_target_group" "aurora" {
  db_proxy_name = aws_db_proxy.aurora.name

  connection_pool_config {
    connection_borrow_timeout    = 120
    max_connections_percent      = 100
    max_idle_connections_percent = 50
  }
}

resource "aws_db_proxy_target" "aurora_cluster" {
  db_cluster_identifier = aws_rds_cluster.aurora.cluster_identifier
  db_proxy_name         = aws_db_proxy.aurora.name
  target_group_name     = aws_db_proxy_default_target_group.aurora.name
}

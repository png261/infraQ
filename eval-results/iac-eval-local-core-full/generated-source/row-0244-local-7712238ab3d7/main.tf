resource "aws_neptune_cluster_parameter_group" "custom" {
  name        = "iac-eval-neptune-cluster-pg"
  family      = "neptune1.2"
  description = "Custom Neptune cluster parameter group for IaC eval benchmark"

  parameter {
    name  = "neptune_enable_audit_log"
    value = "0"
  }
}

resource "aws_neptune_parameter_group" "custom" {
  name        = "iac-eval-neptune-instance-pg"
  family      = "neptune1.2"
  description = "Custom Neptune instance parameter group for IaC eval benchmark"

  parameter {
    name  = "neptune_query_timeout"
    value = "120000"
  }
}

resource "aws_neptune_cluster" "this" {
  cluster_identifier                  = "iac-eval-neptune-cluster"
  engine                              = "neptune"
  neptune_cluster_parameter_group_name = aws_neptune_cluster_parameter_group.custom.name
  skip_final_snapshot                 = true

  tags = {
    Name        = "iac-eval-neptune-cluster"
    Environment = "dev"
  }
}

resource "aws_neptune_cluster_instance" "this" {
  identifier                   = "iac-eval-neptune-instance-1"
  cluster_identifier           = aws_neptune_cluster.this.id
  engine                       = "neptune"
  instance_class               = "db.t4g.medium"
  neptune_parameter_group_name = aws_neptune_parameter_group.custom.name
  publicly_accessible          = false

  tags = {
    Name        = "iac-eval-neptune-instance-1"
    Environment = "dev"
  }
}

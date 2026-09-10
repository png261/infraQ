resource "aws_iam_role" "dax" {
  name = "iac-eval-dax-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "dax.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_dax_cluster" "this" {
  cluster_name       = "iac-eval-dax-cluster"
  iam_role_arn      = aws_iam_role.dax.arn
  node_type         = "dax.r4.large"
  replication_factor = 1
}

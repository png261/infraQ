data "aws_iam_policy_document" "redshift_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["redshift.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "redshift" {
  name               = var.iam_role_name
  assume_role_policy = data.aws_iam_policy_document.redshift_assume_role.json
}

resource "aws_iam_role_policy_attachment" "redshift_s3_readonly" {
  role       = aws_iam_role.redshift.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_redshift_cluster" "example" {
  cluster_identifier = var.cluster_identifier
  database_name      = var.database_name
  master_username    = var.master_username
  master_password    = var.master_password
  node_type          = var.node_type
  cluster_type       = "single-node"

  encrypted           = true
  publicly_accessible = false
  skip_final_snapshot = true
}

resource "aws_redshift_cluster_iam_roles" "example" {
  cluster_identifier = aws_redshift_cluster.example.cluster_identifier
  iam_role_arns      = [aws_iam_role.redshift.arn]

  depends_on = [aws_iam_role_policy_attachment.redshift_s3_readonly]
}

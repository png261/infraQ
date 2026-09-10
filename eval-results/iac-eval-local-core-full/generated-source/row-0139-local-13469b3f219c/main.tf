resource "aws_redshift_cluster" "single_node" {
  cluster_identifier  = "iac-eval-redshift-single-node"
  database_name       = "dev"
  master_username     = "adminuser"
  master_password     = var.redshift_master_password
  node_type           = "dc2.large"
  cluster_type        = "single-node"
  number_of_nodes     = 1
  skip_final_snapshot = true
}

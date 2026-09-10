resource "aws_elasticache_cluster" "memcached" {
  cluster_id           = "iac-eval-memcached"
  engine               = "memcached"
  node_type            = "cache.t4g.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.memcached1.6"
}

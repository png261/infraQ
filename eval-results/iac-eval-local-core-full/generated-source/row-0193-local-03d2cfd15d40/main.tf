resource "aws_elasticache_cluster" "database_cache" {
  cluster_id           = "database-cache-dev"
  engine               = "memcached"
  node_type            = "cache.t3.micro"
  num_cache_nodes      = 1
  parameter_group_name = "default.memcached1.6"
}

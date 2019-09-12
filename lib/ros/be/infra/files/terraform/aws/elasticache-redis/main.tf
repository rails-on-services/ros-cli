resource "aws_security_group" "redis" {
  name_prefix = "${var.name}-redis"
  description = "For redis cluster"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_security_group_rule" "allow-sg-to-redis" {
  count                    = var.allowed_security_groups_count
  type                     = "ingress"
  from_port                = 6379
  to_port                  = 6379
  protocol                 = "tcp"
  source_security_group_id = var.allowed_security_groups[count.index]
  security_group_id        = aws_security_group.redis.id
}

resource "aws_elasticache_replication_group" "this" {
  replication_group_id          = var.name
  replication_group_description = var.name

  automatic_failover_enabled = false
  engine                     = "redis"
  engine_version             = var.engine_version
  at_rest_encryption_enabled = true
  snapshot_retention_limit   = 5
  number_cache_clusters      = var.number_cache_clusters
  node_type                  = var.node_type
  parameter_group_name       = var.parameter_group_name
  subnet_group_name          = var.elasticache_subnet_group_name
  port                       = 6379

  # don't specify availability_zones
  # https://github.com/terraform-providers/terraform-provider-aws/issues/5104
  # availability_zones = ["${data.aws_availability_zones.available.names}"]
  security_group_ids = [aws_security_group.redis.id]

  tags = var.tags
}


module "db" {
  source  = "terraform-aws-modules/rds-aurora/aws"
  name    = var.name
  version = "~> 2.3.0"

  engine                          = var.engine
  engine_version                  = var.engine_version
  instance_type                   = var.instance_type
  performance_insights_enabled    = true
  vpc_id                          = var.vpc_id
  subnets                         = var.subnets
  db_subnet_group_name            = var.db_subnet_group_name
  username                        = var.username
  password                        = var.password
  replica_count                   = var.replica_count
  storage_encrypted               = "true"
  apply_immediately               = "true"
  monitoring_interval             = 10
  db_cluster_parameter_group_name = var.db_cluster_parameter_group_name
  db_parameter_group_name         = var.db_parameter_group_name
  allowed_security_groups         = var.allowed_security_groups

  tags = var.tags
}

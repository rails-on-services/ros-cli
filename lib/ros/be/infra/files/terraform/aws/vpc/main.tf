data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 2.9.0"

  name                = var.name
  cidr                = var.cidr
  tags                = var.tags
  vpc_tags            = var.vpc_tags
  public_subnet_tags  = var.public_subnet_tags
  private_subnet_tags = var.private_subnet_tags

  enable_nat_gateway     = var.enable_nat_gateway
  enable_dns_hostnames   = true
  enable_dns_support     = true
  one_nat_gateway_per_az = true
  enable_s3_endpoint     = true

  create_redshift_subnet_group    = false
  create_database_subnet_group    = var.create_database_subnets
  create_elasticache_subnet_group = var.create_elasticache_subnets

  azs                 = slice(data.aws_availability_zones.available.names, 0, 3)
  public_subnets      = [for i in range(0, 3) : cidrsubnet(var.cidr, 4, i)]
  private_subnets     = [for i in range(3, 6) : cidrsubnet(var.cidr, 4, i)]
  database_subnets    = var.create_database_subnets ? [for i in range(6, 9) : cidrsubnet(var.cidr, 4, i)] : []
  elasticache_subnets = var.create_elasticache_subnets ? [for i in range(9, 12) : cidrsubnet(var.cidr, 4, i)] : []
}

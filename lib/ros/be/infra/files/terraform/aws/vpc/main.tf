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

  azs                 = slice(data.aws_availability_zones.available.names, 0, 3)
  public_subnets      = [for i in range(0, 3) : cidrsubnet(var.cidr, 4, i)]
  private_subnets     = [for i in range(3, 6) : cidrsubnet(var.cidr, 4, i)]
  elasticache_subnets = [for i in range(6, 9) : cidrsubnet(var.cidr, 4, i)]
}

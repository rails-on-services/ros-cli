locals {
  domain_name                      = var.sub_domain != "" ? "${var.sub_domain}.${var.root_domain}" : var.root_domain
  create_ns_records_in_root_domain = var.sub_domain != "" && var.root_domain_managed_in_route53
}

data "aws_route53_zone" "root" {
  name  = "${var.root_domain}."
}

data "aws_route53_zone" "this" {
  name = local.domain_name
}

# If no subdomain defined we deploy into root domain, that we assume already exist.
# So we skip zone creation
resource "aws_route53_zone" "this" {
  count = var.sub_domain != "" ? 1 : 0
  name  = local.domain_name
  tags  = var.tags
}

resource "aws_route53_record" "ns" {
  count   = local.create_ns_records_in_root_domain ? 1 : 0
  zone_id = data.aws_route53_zone.root.zone_id
  name    = aws_route53_zone.this.0.name
  type    = "NS"
  ttl     = 300

  records = aws_route53_zone.this.0.name_servers
}

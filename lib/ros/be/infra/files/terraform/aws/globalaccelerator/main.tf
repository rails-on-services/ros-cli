resource "aws_globalaccelerator_accelerator" "this" {
  name            = var.name
  ip_address_type = "IPV4"
  enabled         = true

  attributes {
    flow_logs_enabled = false
  }
}

resource "aws_route53_record" "globalaccelerator" {
  zone_id = var.route53_zone_id
  name    = var.global_accelerator_hostname
  type    = "A"
  ttl     = "300"
  records = aws_globalaccelerator_accelerator.this.ip_sets[0].ip_addresses
}

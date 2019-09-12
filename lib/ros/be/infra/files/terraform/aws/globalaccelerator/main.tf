resource "aws_globalaccelerator_accelerator" "this" {
  name            = var.name
  ip_address_type = "IPV4"
  enabled         = true

  attributes {
    flow_logs_enabled = false
  }
}

resource "aws_route53_record" "globalaccelerator" {
  count   = var.add_route53_record ? 1 : 0
  zone_id = var.route53_zone_id
  name    = var.route53_record_name
  type    = "A"
  ttl     = "300"
  records = aws_globalaccelerator_accelerator.this.ip_sets[0].ip_addresses
}

resource "aws_globalaccelerator_listener" "this" {
  accelerator_arn = aws_globalaccelerator_accelerator.this.id
  client_affinity = "NONE"
  protocol        = "TCP"

  port_range {
    from_port = 80
    to_port   = 80
  }
  port_range {
    from_port = 433
    to_port   = 433
  }
}

resource "aws_globalaccelerator_endpoint_group" "this" {
  count                 = var.add_elb_listener ? 1 : 0
  listener_arn          = aws_globalaccelerator_listener.this.id
  health_check_protocol = "TCP"
  health_check_port     = 80

  endpoint_configuration {
    endpoint_id = var.elb_endpoint
    weight      = 100
  }

  lifecycle {
    ignore_changes = [
      health_check_path,
    ]
  }
}

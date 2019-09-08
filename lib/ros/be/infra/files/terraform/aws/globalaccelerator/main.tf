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

data "external" "elb_arn" {
  program = ["python", "${path.module}/files/get_alb_arn.py"]

  query = {
    config_name = "${var.cluster_name}_config.yaml",
    aws_profile  = var.aws_profile

  }
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
  count             = data.external.elb_arn.result.LoadBalancerArn != "" ? 1 : 0
  listener_arn      = aws_globalaccelerator_listener.this.id
  health_check_path = "/"
  health_check_port = 80

  endpoint_configuration {
    endpoint_id = data.external.elb_arn.result.LoadBalancerArn
    weight      = 100
  }
}
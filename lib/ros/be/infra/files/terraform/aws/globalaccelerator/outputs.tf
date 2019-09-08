output "globalaccelerator_ips" {
  description = "IPs of global accelerator"
  value = flatten(
    aws_globalaccelerator_accelerator.this.*.ip_sets.0.ip_addresses,
  )
}


output "alb_arn" {
  value = data.external.alb_arn.result.LoadBalancerArn
}
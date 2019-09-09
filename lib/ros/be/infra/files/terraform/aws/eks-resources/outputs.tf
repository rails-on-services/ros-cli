
output "alb_arn" {
  value = data.external.alb_arn.result.LoadBalancerArn
}

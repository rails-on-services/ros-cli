
output "istio_ingressgateway_alb_arn" {
  value = data.external.alb_arn.result.LoadBalancerArn
}

output "ros_repo" {
  value = data.helm_repository.ros
}

output "incubator" {
  value = data.helm_repository.incubator
}

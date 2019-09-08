variable "region" {
  default = "ap-southeast-1"
  type    = string
}

variable "aws_profile" {
  default = "deafult"
  type    = string
}

variable "vpc_id" {
  default = ""
  type    = string
}

variable "kubeconfig" {
  default = ""
  type    = string
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name"
}

variable "extra_namespaces" {
  type        = list(string)
  description = "extra kubernetes namespaces to create"
  default     = []
}

# TODO, remove this feature, not in use anymore since external service doesn't play well with istio
variable "k8s_mapping_external_services" {
  type        = list(map(string))
  description = "external services created inside k8s, list of hash with mandatory keys (name, externalName) and optional keys (namespace)"
  default     = []
}

variable "enable_fluentd_gcp_logging" {
  default     = false
  description = "Whether to deploy fluentd-gcp to collect node and container logs"
}

variable "fluentd_gcp_logging_service_account_json_key_path" {
  default     = ""
  description = "The path to the google service account json key used for fluentd-gcp logging"
}

variable "clusterrolebindings" {
  default     = []
  description = "List of map of clusterroblebindings, currently only group as subject is supportd. A map should contain keys: name, clusterrole, group"
}

variable "enable_external_dns" {
  default     = false
  description = "Whether to deploy external-dns with Route53"
}

variable "external_dns_route53_zone_type" {
  default = "public"
}

variable "external_dns_domainFilters" {
  type    = list(string)
  default = []
}

variable "external_dns_zoneIdFilters" {
  type    = list(string)
  default = []
}

variable "enable_istio" {
  default     = true
  description = "Enable istio with ingress gateway as NodePort service"
}

variable "istio_version" {
  default     = "1.2.4"
  description = "Istio version to install"
}

variable "istio_ingressgateway_alb_cert_arn" {
  default     = ""
  description = "[Optional] The AWS TLS certificates ARN (in IAM or ACM) for istio ALB ingress gateway"
}


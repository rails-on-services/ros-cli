variable "name" {
  type    = string
  default = ""
}

variable "route53_zone_id" {
  type        = string
  default     = ""
  description = "[Optional] route53 zone id"
}

variable "global_accelerator_hostname" {
  type        = string
  default     = ""
  description = "[Optional] DNS name of the global accelerator to be added to route53 zone"
}

variable "aws_profile" {
  default     = "deafult"
  type        = string
  description = "AWS profile value"
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name"
}
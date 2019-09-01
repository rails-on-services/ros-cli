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
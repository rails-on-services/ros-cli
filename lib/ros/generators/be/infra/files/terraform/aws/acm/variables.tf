variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the created resources"
}

variable "domain_name" {
  type        = string
  description = "The domain name for the ACM cert"
}

variable "route53_domain_name" {
  default     = ""
  type        = string
  description = "The route53 domain name to add DNS validation records into, need to specify if it's different than domain_name"
}

variable "subject_alternative_names" {
  default = []
  type    = set(string)
}

variable "route_53_dns_validation" {
  default     = true
  description = "Add DNS validation record to route53 zone automatically"
}

variable "route53_dns_record_count" {
  default     = 1
  description = "Number of cert_validation records to be created"
}

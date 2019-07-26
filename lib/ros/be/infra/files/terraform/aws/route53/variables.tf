variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the created resources"
}

variable "root_domain" {
  type        = string
  description = "The root domain to use"
}

variable "sub_domain" {
  default     = ""
  type        = string
  description = "OPTIONAL, sub-domain (omit the root domain) of the root domain"
}

variable "root_domain_managed_in_route53" {
  default     = false
  description = "Specify if the sub_domain is not empty and root domain is managed already in route53, will add sub_domain's NS to root_domain's zone"
}

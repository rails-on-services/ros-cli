variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the created resources"
}

variable "aws_profile" {
  type    = string
  default = "default"
}

variable "s3_bucket_name" {
  type        = string
  description = "S3 bucket name"
}

variable "cloudfront_cname" {
  type        = string
  description = "Alternate domain name for cloudfront"
}

variable "acm_certificate_arn" {
  type        = string
  default     = ""
  description = "[Optional] The existing ACM certificate to be used (must be in region US-EAST-1)"
}

variable "create_acm_certificate" {
  type        = bool
  default     = false
  description = "[Optional] Create a new acm cert with cloudfront_cname"
}

variable "add_route53_record" {
  type    = bool
  default = true
}

variable "route53_zone_id" {
  type        = string
  default     = ""
  description = "[Optional] route53 zone id"
}

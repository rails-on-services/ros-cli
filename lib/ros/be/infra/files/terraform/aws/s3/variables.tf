variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the created resources"
}

variable "s3_bucket_names" {
  type    = list(string)
  default = []
  description = "List of buckets to be created"
}

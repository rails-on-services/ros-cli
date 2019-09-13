variable "name" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map
  default = {}
}

variable "vpc_id" {
  type = string
}

variable "engine_version" {
  type    = string
  default = "5.0.4"
}

variable "node_type" {
  type    = string
  default = "cache.r5.large"
}

variable "number_cache_clusters" {
  type    = number
  default = 1
}

variable "parameter_group_name" {
  type    = string
  default = "default.redis5.0"
}

variable "elasticache_subnet_group_name" {
  type = string
}

variable "allowed_security_groups" {
  type    = list(string)
  default = []
}

variable "allowed_security_groups_count" {
  type    = number
  default = 0
}

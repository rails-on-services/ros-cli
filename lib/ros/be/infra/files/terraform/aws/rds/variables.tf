variable "name" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map
  default = {}
}

variable "engine" {
  type    = string
  default = "aurora-postgresql"
}

variable "engine_version" {
  type    = string
  default = "10.7"
}

variable "instance_type" {
  type    = string
  default = "db.r5.large"
}

variable "vpc_id" {
  type = string
}

variable "subnets" {
  type    = list(string)
  default = []
}

variable "db_subnet_group_name" {
  type    = string
  default = ""
}

variable "username" {
  type    = string
  default = "postgres"
}

variable "password" {
  type    = string
  default = ""
}

variable "replica_count" {
  type    = string
  default = 1
}

variable "db_cluster_parameter_group_name" {
  type    = string
  default = "default.aurora-postgresql10"
}

variable "db_parameter_group_name" {
  type    = string
  default = "default.aurora-postgresql10"
}

variable "allowed_security_groups" {
  type    = list(string)
  default = []
}

variable "allowed_security_groups_count" {
  type    = number
  default = 0
}

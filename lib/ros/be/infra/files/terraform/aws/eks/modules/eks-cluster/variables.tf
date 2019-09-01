variable "tags" {
  type    = map
  default = {}
}

variable "cluster_name" {
  type    = string
  default = ""
}

variable "vpc_id" {
  type    = string
  default = ""
}

variable "public_subnets" {
  type = list(string)
  default = []
}

variable "private_subnets" {
  type = list(string)
  default = []
}
variable "default_security_group_id" {
  type    = string
  default = ""
}

variable "eks_worker_ami_name_filter" {
  type    = string
  default = "v*"
}

variable "eks_cluster_enabled_log_types" {
  default = []
}

variable "eks_worker_groups" {
  type    = any
  default = []
}

variable "eks_map_users" {
  type        = list(map(string))
  default     = []
  description = "IAM users to add to the aws-auth configmap, see example here: https://github.com/terraform-aws-modules/terraform-aws-eks/blob/master/examples/eks_test_fixture/variables.tf"
}

variable "eks_map_roles" {
  type        = list(map(string))
  default     = []
  description = "IAM roles to add to the aws-auth configmap, see example here: https://github.com/terraform-aws-modules/terraform-aws-eks/blob/master/examples/eks_test_fixture/variables.tf"
}
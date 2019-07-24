variable "name" {
  description = "Name of the VPC"
}

variable "cidr" {
  default     = "10.1.0.0/16"
  description = "CIDR of the VPC"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the created resources"
}

variable "vpc_tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags for the vpc"
}

variable "public_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags for the public subnets"
}

variable "private_subnet_tags" {
  type        = map(string)
  default     = {}
  description = "Additional tags for the private subnets"
}

variable "enable_nat_gateway" {
  default     = true
  description = "Whether to enable nat gateway for private subnets"
}

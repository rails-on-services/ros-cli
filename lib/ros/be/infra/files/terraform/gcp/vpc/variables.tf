variable "vpc_name" {
    description = "The name of the VPC being created."
    type        = string
}

variable "subnet_name" {
    description = "The name of the VPC being created."
    type        = string
}

variable "create_subnetworks" {
    description = "When set to true, the network is created in 'auto subnet mode' and it will create a subnet for each region automatically across the 10.128.0.0/9 address range. When set to false, the network is created in 'custom subnet mode' so the user can explicitly connect subnetwork resources."
    type        = bool
}

variable "cidr" {
  description = "CIDR"
  type        = string
}
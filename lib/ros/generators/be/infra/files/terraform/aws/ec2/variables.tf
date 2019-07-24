variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for the created resources"
}

variable "name_prefix" {
  default     = "ros"
  type        = string
  description = "Name prefix for created resources"
}

variable "project_name" {
  default     = "dev"
  type        = string
  description = "The project name used by cloud-init userdata"
}


variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type    = list
  default = []
}

variable "ec2_instance_type" {
  default = "t3.large"
}

variable "ec2_ami_distro" {
  default     = "debian"
  description = "The EC2 ami linux distro to use, can be debian or ubuntu"
}

variable "ec2_key_pair" {
  default     = null
  description = "EC2 ssh key pair name to use"
}

variable "ssh_public_keys" {
  default     = []
  type        = list
  description = "List of public keys to add to the instance's ~/.ssh/authorized_keys"
}


variable "aws_cert_arn" {
  type        = string
  description = "AWS ACM cert arn to be used by the created load balancer"
}

variable "lb_dns_hostnames" {
  default     = []
  type        = list
  description = "Optional, DNS records for adding to route53 for the load balancer"
}

variable "route53_zone_id" {
  default     = ""
  type        = string
  description = "Optional, Route53 hosted zone ID to add records into, mandatory if lb_dns_hostnames is specified"
}

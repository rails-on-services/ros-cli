variable "name" {
    description = "Instance name"
    type        = string
}

variable "machine_type" {
    description = "Instance machine type"
    type        = string
}

variable "dick_image" {
    description = "Instance disk image"
    type        = string    
}

variable "zone" {
    description = "Instance availability zone"
    type        = string    
}

variable "subnetwork" {
    description = "The name or self_link of the subnetwork to attach this instance network interface to."
    type        = string    
}
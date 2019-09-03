variable "name" {
    description = "Instance name"
    type        = string
}

variable "machine_type" {
    description = "Instance machine type"
    type        = string
}

variable "disk_image" {
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

variable "project_name" {  
  description = "The project name used by metadata_startup_script"  
  type        = string
  default     = "dev"
}

variable "ssh_public_key" {  
  description = "Public SSH key to be added to authorized_keys"  
  type        = string
}
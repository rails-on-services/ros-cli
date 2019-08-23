 locals {
  disk_image_map = {
    debian = "debian-cloud/debian-9"
    ubuntu = "ubuntu-os-cloud/ubuntu-1804-lts"
  }

  user_map = {
    debian = "admin"
    ubuntu = "ubuntu"
  }
}

resource "google_compute_instance" "this" {
  name         = var.name
  machine_type = var.machine_type
  zone         = var.zone
  
  boot_disk {
    initialize_params {
      image = local.disk_image_map[var.disk_image]
    }
  }

  network_interface {
    subnetwork = var.subnetwork   
    access_config {}
  }

  metadata_startup_script = templatefile("${path.module}/templates/startup-script.tpl", {
    project_name   = var.project_name,
    user           = local.user_map[var.disk_image],
    ssh_public_key = var.ssh_public_key
  })
}
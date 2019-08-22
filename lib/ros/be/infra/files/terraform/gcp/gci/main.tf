resource "google_compute_instance" "this" {
  name         = var.name
  machine_type = var.machine_type
  zone         = var.zone
  
  boot_disk {
    initialize_params {
      image = var.disk_image
    }
  }

  network_interface {
    subnetwork = var.subnetwork   
    access_config {}
  }  
}
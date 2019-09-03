resource "google_compute_network" "this" {
  name                    = var.vpc_name
  auto_create_subnetworks = var.create_subnetworks
}

resource "google_compute_subnetwork" "this" {
  name          = var.subnet_name
  ip_cidr_range = var.cidr
  network       = google_compute_network.this.self_link
}

resource "google_compute_firewall" "this" {
  name          = "allow-ssh"
  network       = google_compute_network.this.name
  source_ranges = ["0.0.0.0/0"]
  
  allow {
    protocol = "icmp"
  }

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
}
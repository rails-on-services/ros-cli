resource "google_compute_network" "this" {
  name                    = var.vpc_name
  auto_create_subnetworks = var.create_subnetworks
}

resource "google_compute_subnetwork" "this" {
  name          = var.subnet_name
  ip_cidr_range = var.cidr
  network       = google_compute_network.this.self_link
}
output "network" {
  value = google_compute_network.this 
}

output "subnetwork" {
  value = google_compute_subnetwork.this
}

output "firewall" {
  value = google_compute_firewall.this
}
output "google_compute_instance_id" {
  description = "ID of the created Google Compute Instance."
  value       = google_compute_instance.gns3.instance_id
}

locals {
  public_ip = google_compute_instance.gns3.network_interface[0].access_config[0].nat_ip
}

output "public_ip" {
  description = "Public IP address of the created instance."
  value       = local.public_ip
}

output "openvpn_profile_endpoint" {
  description = "Endpoint to download the OpenVPN profile from."
  value       = "http://${local.public_ip}:${var.openvpn_profile_endpoint_port}/profile/gns3-server.ovpn"
}

output "gns3_server_ip" {
  description = "Private IP that the GNS3 server will listen for connections on. Set the remote server host to this value in the GNS3 client UI."
  value       = var.gns3_server_ip
}

output "gns3_server_port" {
  description = "Port used to connect to the GNS3 server. Set the remote server port to this value in the GNS3 client UI."
  value       = var.gns3_server_port
}

data "http" "curr_ip" {
  count = var.allow_ingress_from_current_ip ? 1 : 0
  url   = "http://ipv4.icanhazip.com"
}

locals {
  allowed_cidr_blocks = concat(var.allowed_ingress_cidr_blocks, [for x in data.http.curr_ip : "${chomp(x.body)}/32"])
}

resource "google_compute_firewall" "openvpn" {
  name        = "${var.name}-allow-openvpn-traffic"
  description = "Allow ingress traffic for OpenVPN."
  network     = var.vpc_network

  source_ranges = local.allowed_cidr_blocks

  allow {
    protocol = "tcp"
    ports    = ["22", var.openvpn_profile_endpoint_port]
  }

  allow {
    protocol = "udp"
    ports    = [var.openvpn_access_port]
  }

  target_tags = ["openvpn"]
}

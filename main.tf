locals {
  labels = {
    part_of    = "gns3_server"
    managed_by = "terraform"
  }
}

data "google_compute_image" "gns3" {
  name    = var.image_name
  family  = var.image_family
  project = var.image_project
}

resource "google_compute_instance" "gns3" {
  name        = var.name
  description = "Google Compute Instance hosting a remote GNS3 server and an OpenVPN server."

  machine_type              = var.machine_type
  min_cpu_platform          = var.min_cpu_platform
  allow_stopping_for_update = true
  can_ip_forward            = true

  desired_status = var.enable_server ? "RUNNING" : "TERMINATED"

  boot_disk {
    initialize_params {
      image = data.google_compute_image.gns3.self_link
    }
  }

  attached_disk {
    source      = google_compute_disk.gns3.self_link
    device_name = "gns3-storage"
  }

  network_interface {
    network = var.vpc_network
    access_config {}
  }

  tags   = ["openvpn"]
  labels = local.labels

  metadata = merge(
    {
      ovpn_access_port           = var.openvpn_access_port
      ovpn_profile_endpoint_port = var.openvpn_profile_endpoint_port
      gns3_server_ip             = var.gns3_server_ip
      gns3_server_port           = var.gns3_server_port
    },
    var.openvpn_profile_endpoint_creds == null ? {} :
    {
      ovpn_profile_endpoint_auth_enabled = "true"
      ovpn_profile_endpoint_user         = var.openvpn_profile_endpoint_creds.username
      ovpn_profile_endpoint_pass         = var.openvpn_profile_endpoint_creds.password
    }
  )

  metadata_startup_script = file("${path.module}/scripts/setup-openvpn.sh")
}

resource "google_compute_disk" "gns3" {
  name        = "${var.name}-gns3-storage-disk"
  description = "Persistent disk used to store GNS3 files such as project, image and appliance files."

  type = "pd-standard"
  size = var.gns3_disk_size
}

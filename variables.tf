## Required Parameters ##

variable "machine_type" {
  type        = string
  description = "Machine type to use for the Google Compute Instance."
}

variable "gns3_disk_size" {
  type        = number
  description = "Size (in GB) for the persistent disk used to store GNS3 files (images, appliances etc.)"
}

variable "image_name" {
  type        = string
  description = "Name of the GNS3 server base image to be used for the Google Compute Instance. Exactly one of `image_name` or `image_family` must be specified."
  default     = null
}

variable "image_family" {
  type        = string
  description = "Image family for a GNS3 server base image to be used for the Google Compute Instance. Exactly one of `image_name` or `image_family` must be specified."
  default     = null
}

## Optional Parameters ##

variable "name" {
  type        = string
  description = "Name to use for resources created by Terraform."
  default     = "gns3-server"
}

variable "enable_server" {
  type        = bool
  description = "If true, sets the Google Compute Instance to a running state. Otherwise, stops the instance."
  default     = true
}

variable "image_project" {
  type        = string
  description = "Project where the GNS3 server base image to be used belongs to. Required to use a public base image."
  default     = null
}

variable "min_cpu_platform" {
  type        = string
  description = "Minimum CPU platform to use for the Google Compute Instance. Your instance may need certain minimum CPU platforms to support nested virtualization, which is required for GNS3. Examples include \"Intel Skylake\" or \"Intel Haswell\"."
  default     = null
}

variable "vpc_network" {
  type        = string
  description = "Network to launch the Google resources in."
  default     = "default"
}

variable "allow_ingress_from_current_ip" {
  type        = bool
  description = "When enabled, the Google Compute Instance will allow inbound connections from your current IP address. Should consider disabling if your IP address is expected to not be stable."
  default     = true
}

variable "allowed_ingress_cidr_blocks" {
  type        = list(string)
  description = "Additional list of CIDR blocks that the Google Compute Instance will allow inbound connections from. Can be used to enable connections when `ingress_from_current_ip_only` is disabled."
  default     = []
}

variable "openvpn_access_port" {
  type        = number
  description = "Port used to access the OpenVPN access server."
  default     = 1194
}

variable "openvpn_profile_endpoint_port" {
  type        = number
  description = "Port used to download the OpenVPN client profile."
  default     = 8003
}

variable "openvpn_profile_endpoint_creds" {
  type = object({
    username = string
    password = string
  })
  description = "Credentials required for authentication to download the OpenVPN client profile from the server endpoint. Default uses no authentication."
  default     = null
}

variable "gns3_server_ip" {
  type        = string
  description = "Private IP that the GNS3 server will listen for connections on within the OpenVPN network. Should be in the 172.16.253.0/24 subnet."
  default     = "172.16.253.1"
}

variable "gns3_server_port" {
  type        = number
  description = "Port used to connect to the GNS3 server."
  default     = 3080
}

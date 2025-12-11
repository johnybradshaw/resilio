# data.tf
# Data sources for external information

# Fetch the current public IP address of the machine running Terraform
# This is used to automatically configure allowed_ssh_cidr for secure access
data "http" "current_ip" {
  url = "https://ifconfig.me/ip"

  request_headers = {
    Accept = "text/plain"
  }
}

# Local value to convert IP to CIDR notation
locals {
  current_ip_cidr = "${trimspace(data.http.current_ip.response_body)}/32"
}

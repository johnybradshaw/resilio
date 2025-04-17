# modules/linode/variables.tf
variable "region" {
  description = "Linode region"
  type        = string
}

variable "instance_type" {
  description = "Linode instance type"
  type        = string
}

variable "ssh_public_key" {
  description = "SSH public key for accessing the instance"
  type        = string
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "volume_id" {
  description = "ID of the volume to attach"
  type        = string
}

variable "resilio_folder_key" {
  description = "Resilio Sync folder key"
  type        = string
  sensitive   = true
}

variable "resilio_license_key" {
  description = "Resilio Sync license key"
  type        = string
  sensitive   = true
}

variable "ubuntu_advantage_token" {
  description = "Ubuntu Advantage token"
  type = string
  sensitive = true
}

variable "tld" {
  description = "Top-Level Domain (TLD)"
  type = string
}
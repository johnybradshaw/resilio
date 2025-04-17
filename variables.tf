# variables.tf
variable "linode_token" {
  description = "Linode API token"
  type        = string
  sensitive   = true
}

variable "regions" {
  description = "List of Linode regions to deploy to"
  type        = list(string)
  default     = ["us-east", "eu-west"]
}

variable "resilio_folder_key" {
  description = "Resilio Sync folder key to automatically add"
  type        = string
  sensitive   = true
}

variable "resilio_license_key" {
  description = "Resilio Sync license key"
  type = string
  sensitive = true
}

variable "ssh_public_key" {
  description = "SSH public key for accessing the instances"
  type        = string
}

variable "instance_type" {
  description = "Linode instance type"
  type        = string
  default     = "g6-standard-1"
}

variable "volume_size" {
  description = "Size of the storage volume in GB"
  type        = number
  default     = 20
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "resilio-sync"
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
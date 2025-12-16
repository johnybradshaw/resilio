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

variable "resilio_folder_keys" {
  description = "List of Resilio Sync folder keys"
  type        = list(string)
  sensitive   = true
}

# Keep old variable for backward compatibility
variable "resilio_folder_key" {
  description = "[DEPRECATED] Use resilio_folder_keys instead"
  type        = string
  sensitive   = true
  default     = ""
}

variable "resilio_license_key" {
  description = "Resilio Sync license key"
  type        = string
  sensitive   = true
}

variable "ubuntu_advantage_token" {
  description = "Ubuntu Advantage token"
  type        = string
  sensitive   = true
}

variable "tld" {
  description = "Top-Level Domain (TLD)"
  type        = string
}

variable "tags" {
  description = "Set of tags to apply to all resources"
  type        = list(string)
  default     = ["deployment: terraform", "app: resilio"]
}

variable "firewall_id" {
  description = "ID of the firewall to attach to this instance"
  type        = string
}

variable "object_storage_access_key" {
  description = "Linode Object Storage access key for backups"
  type        = string
  sensitive   = true
}

variable "object_storage_secret_key" {
  description = "Linode Object Storage secret key for backups"
  type        = string
  sensitive   = true
}

variable "object_storage_endpoint" {
  description = "Linode Object Storage endpoint"
  type        = string
}

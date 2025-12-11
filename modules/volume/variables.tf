# modules/volume/variables.tf
variable "region" {
  description = "Linode region"
  type        = string
}

variable "size" {
  description = "Size of the volume in GB"
  type        = number
}

variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "tags" {
  description = "Set of tags to apply to all resources"
  type        = list(string)
  default     = ["deployment: terraform", "app: resilio"]
}

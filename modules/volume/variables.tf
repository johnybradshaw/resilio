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
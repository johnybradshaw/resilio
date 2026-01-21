# modules/volume/variables.tf
variable "region" {
  description = "Linode region"
  type        = string
}

variable "folders" {
  description = "Map of folder names to their configurations"
  type = map(object({
    key  = string
    size = number
  }))
  sensitive = true
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

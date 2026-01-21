# modules/jumpbox-firewall/variables.tf

variable "project_name" {
  description = "Project name prefix"
  type        = string
}

variable "suffix" {
  description = "Global suffix shared across all resources (from random_id.global_suffix)"
  type        = string
}

variable "tags" {
  description = "Set of tags to apply to all resources"
  type        = list(string)
  default     = ["deployment: terraform", "app: resilio"]
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH/ping access to jumpbox (e.g., '1.2.3.4/32')"
  type        = string
  default     = "0.0.0.0/0" # Default allows all - should be overridden for security
}

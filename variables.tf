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

  validation {
    condition     = length(var.regions) > 0
    error_message = "At least one region must be specified."
  }
}

# New per-folder volume configuration (recommended)
variable "resilio_folders" {
  description = "Map of Resilio Sync folders with their keys and volume sizes. Each folder gets a dedicated volume."
  type = map(object({
    key  = string # Resilio folder key (sensitive)
    size = number # Volume size in GB
  }))
  sensitive = true
  default   = {}

  validation {
    condition = alltrue([
      for name, config in var.resilio_folders :
      can(regex("^[a-z0-9]([a-z0-9-]*[a-z0-9])?$", name)) && length(name) >= 2 && length(name) <= 32
    ])
    error_message = "Folder names must be 2-32 characters, lowercase alphanumeric with hyphens (no leading/trailing hyphens)."
  }

  validation {
    condition = alltrue([
      for name, config in var.resilio_folders :
      config.size >= 10 && config.size <= 10000
    ])
    error_message = "Volume size must be between 10 and 10000 GB."
  }

  validation {
    condition = alltrue([
      for name, config in var.resilio_folders :
      length(config.key) >= 20
    ])
    error_message = "Resilio folder keys must be at least 20 characters."
  }

  validation {
    condition     = length(keys(var.resilio_folders)) <= 13
    error_message = "Maximum 13 folders per instance (limited by device letters)."
  }
}

# [DEPRECATED] Legacy variables - use resilio_folders instead
variable "resilio_folder_keys" {
  description = "[DEPRECATED] Use resilio_folders instead. List of Resilio Sync folder keys."
  type        = list(string)
  sensitive   = true
  default     = []
}

variable "resilio_folder_key" {
  description = "[DEPRECATED] Use resilio_folders instead. Single Resilio Sync folder key."
  type        = string
  sensitive   = true
  default     = ""
}

variable "resilio_license_key" {
  description = "Resilio Sync license key"
  type        = string
  sensitive   = true
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

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "resilio-sync"
}

variable "ubuntu_advantage_token" {
  description = "Ubuntu Advantage token"
  type        = string
  sensitive   = true
}

variable "tld" {
  description = "Top-Level Domain (TLD)"
  type        = string

  validation {
    condition     = can(regex("^([a-z0-9][a-z0-9-]{0,61}[a-z0-9]\\.)+[a-z]{2,}$", var.tld))
    error_message = "TLD must be a valid domain name (e.g., 'example.com' or 'subdomain.example.com')."
  }
}

variable "dns_include_project_name" {
  description = "Whether to include project name in DNS records. If true: us-east.resilio-sync.domain.tld, if false: us-east.domain.tld"
  type        = bool
  default     = true
}

variable "create_domain" {
  description = "Whether to create the domain in Linode DNS or use an existing one. Set to false if domain already exists."
  type        = bool
  default     = false # Default to false since most users will have existing domains
}

variable "acme_server_url" {
  description = "ACME server URL for Let's Encrypt certificates. Use staging for testing to avoid rate limits."
  type        = string
  default     = "https://acme-v02.api.letsencrypt.org/directory"
  # Staging URL: "https://acme-staging-v02.api.letsencrypt.org/directory"
}

variable "tags" {
  description = "Set of tags to apply to all resources"
  type        = list(string)
  default     = ["deployment: terraform", "app: resilio"]
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed for SSH/ping access to jumpbox. Defaults to auto-detected current IP. Set to '0.0.0.0/0' to allow all (NOT recommended)."
  type        = string
  default     = null # Will be auto-detected if not specified

  validation {
    condition     = var.allowed_ssh_cidr == null || can(cidrhost(var.allowed_ssh_cidr, 0))
    error_message = "Must be a valid CIDR block (e.g., '1.2.3.4/32' or '0.0.0.0/0')."
  }
}

variable "allowed_webui_cidr" {
  description = "CIDR block allowed for HTTPS web UI access to Resilio instances. Defaults to auto-detected current IP. Set to '0.0.0.0/0' to allow all (NOT recommended for production)."
  type        = string
  default     = null # Will be auto-detected if not specified

  validation {
    condition     = var.allowed_webui_cidr == null || can(cidrhost(var.allowed_webui_cidr, 0))
    error_message = "Must be a valid CIDR block (e.g., '1.2.3.4/32' or '0.0.0.0/0')."
  }
}

variable "jumpbox_region" {
  description = "Linode region for the jumpbox (bastion host)"
  type        = string
  default     = "us-east"
}

variable "jumpbox_instance_type" {
  description = "Linode instance type for the jumpbox"
  type        = string
  default     = "g6-nanode-1" # Smallest instance (1GB RAM, 1 vCPU) - sufficient for jumpbox
}

# =============================================================================
# BACKUP CONFIGURATION
# =============================================================================

variable "backup_enabled" {
  description = "Enable Object Storage backups. When true, Terraform will create and manage backup buckets and keys."
  type        = bool
  default     = false
}

variable "backup_storage_regions" {
  description = "Compute region IDs in which to create backup Object Storage buckets (e.g. 'us-east', 'eu-central'). NOTE: use the COMPUTE region id, not the cluster/endpoint id. The API accepts 'us-east-1' on create but stores 'us-east', and because `region` is force-new that mismatch puts the bucket in a permanent replacement loop."
  type        = list(string)
  default     = ["us-east"]

  validation {
    condition = alltrue([
      for region in var.backup_storage_regions :
      contains([
        "ap-south", "au-mel", "br-gru", "de-fra-2", "es-mad", "eu-central",
        "fr-par", "gb-lon", "id-cgk", "in-maa", "it-mil", "jp-osa", "jp-tyo-3",
        "nl-ams", "se-sto", "sg-sin-2", "us-east", "us-iad", "us-iad-2",
        "us-lax", "us-mia", "us-ord", "us-sea", "us-southeast",
      ], region)
    ])
    error_message = "Invalid Object Storage region. Use the COMPUTE region id (e.g. 'us-east', 'eu-central'), NOT the cluster id ('us-east-1'). List current regions with: linode-cli object-storage clusters-list"
  }
}

variable "backup_source_regions" {
  description = "List of VM regions that should run backups. Only VMs in these regions will push to Object Storage. Empty = no VMs backup. For efficiency, recommend only one region since all VMs sync the same data."
  type        = list(string)
  default     = [] # Set to ["us-east"] to have one region backup

  # backup_enabled = true with no source regions creates buckets and an access
  # key, bills for them, reports backup_enabled = true in the outputs - and
  # backs up nothing, because contains([], region) is false for every region.
  validation {
    condition     = !var.backup_enabled || length(var.backup_source_regions) > 0 || length(var.backup_regions) > 0
    error_message = "backup_enabled is true but backup_source_regions is empty, so NO instance will run a backup. Set it to at least one region."
  }

  # A typo'd region is otherwise a silent no-op: it has no instance, so nothing
  # backs up and nothing reports a problem.
  validation {
    condition     = alltrue([for r in var.backup_source_regions : contains(var.regions, r)])
    error_message = "backup_source_regions contains a region not present in var.regions; that region has no instance and will never back up."
  }
}

variable "backup_versioning" {
  description = "Enable object versioning for backup buckets (recommended for data protection and recovery)"
  type        = bool
  default     = true
}

variable "backup_retention_days" {
  description = "Number of days to retain backup versions. Old versions are automatically cleaned up. Set to 0 to keep forever."
  type        = number
  default     = 90

  validation {
    condition     = var.backup_retention_days >= 0
    error_message = "Retention days must be 0 or greater."
  }
}

variable "backup_mode" {
  description = "Backup scheduling mode: 'scheduled' (cron-based), 'realtime' (inotify-based immediate sync), or 'hybrid' (realtime + daily full sync)"
  type        = string
  default     = "scheduled"

  validation {
    condition     = contains(["scheduled", "realtime", "hybrid"], var.backup_mode)
    error_message = "Backup mode must be 'scheduled', 'realtime', or 'hybrid'."
  }
}

variable "backup_schedule" {
  description = "Cron schedule for backups (used in 'scheduled' and 'hybrid' modes). Default: daily at 2 AM."
  type        = string
  default     = "0 2 * * *"
}

variable "backup_transfers" {
  description = "Number of parallel file transfers for rclone (higher = faster but more CPU/IO)"
  type        = number
  default     = 8

  validation {
    condition     = var.backup_transfers >= 1 && var.backup_transfers <= 32
    error_message = "Backup transfers must be between 1 and 32."
  }
}

variable "backup_bandwidth_limit" {
  description = "Bandwidth limit for backups in bytes/sec (e.g., '10M' for 10MB/s). Empty string = unlimited."
  type        = string
  default     = ""
}

variable "backup_bucket_prefix" {
  description = "Prefix for backup bucket names (will be suffixed with region)"
  type        = string
  default     = "resilio-backup"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.backup_bucket_prefix)) || var.backup_bucket_prefix == ""
    error_message = "Bucket prefix must be lowercase alphanumeric with hyphens."
  }
}

# Legacy variables - kept for backward compatibility
# These are used if backup_enabled = false and manual credentials are provided
variable "object_storage_access_key" {
  description = "[LEGACY] Manual Object Storage access key. Use backup_enabled=true for Terraform-managed backups."
  type        = string
  sensitive   = true
  default     = "CHANGEME"
}

variable "object_storage_secret_key" {
  description = "[LEGACY] Manual Object Storage secret key. Use backup_enabled=true for Terraform-managed backups."
  type        = string
  sensitive   = true
  default     = "CHANGEME"
}

variable "object_storage_endpoint" {
  description = "[LEGACY] Manual Object Storage endpoint. Use backup_enabled=true for Terraform-managed backups."
  type        = string
  default     = "us-east-1.linodeobjects.com"
}

variable "object_storage_bucket" {
  description = "[LEGACY] Manual Object Storage bucket. Use backup_enabled=true for Terraform-managed backups."
  type        = string
  default     = "resilio-backups"
}

variable "backup_regions" {
  description = "[DEPRECATED] Use backup_source_regions instead. List of VM regions that should run backups."
  type        = list(string)
  default     = []
}

variable "cloud_user" {
  description = "Non-root user for SSH access and management"
  type        = string
  default     = "ac-user"
}

# =============================================================================
# SCRIPT PROVISIONING (phase 2)
# =============================================================================
# Cloud-init installs PLACEHOLDER versions of resilio-backup.sh,
# resilio-rehydrate.sh, resilio-backup-watch.sh and collect-diagnostics.sh, to
# stay inside the user_data size limit. The real scripts are transferred over
# SSH afterwards by null_resource.provision_scripts in modules/linode.
#
# That resource is gated on provision_scripts, which the root module previously
# never declared or passed - so it was permanently false and the real scripts
# were NEVER delivered to any instance. The backup placeholder logs one line and
# exits 0, which cron records as success, so backups appeared healthy while
# doing nothing. Rebuilding an instance silently downgraded it.

variable "provision_scripts" {
  description = "Transfer the full management scripts to instances over SSH after boot. Without this, instances keep the cloud-init placeholders and backups DO NOT RUN. Requires ssh_private_key."
  type        = bool
  default     = false
}

variable "ssh_private_key" {
  description = "Private key matching ssh_public_key, used by the file provisioner via the jumpbox. Required when provision_scripts is true. Supply via TF_VAR_ssh_private_key - a .tfvars file cannot call file()."
  type        = string
  sensitive   = true
  default     = ""

  # A `check` block was used here first. check blocks only emit WARNINGS: the
  # plan and apply proceed, so an apply could start before failing later. That
  # is the same quiet failure this whole change removes. Cross-variable
  # validation errors properly, and is available since Terraform 1.9 (the root
  # module requires >= 1.10.0).
  validation {
    condition     = !var.provision_scripts || var.ssh_private_key != ""
    error_message = "provision_scripts is true but ssh_private_key is empty. The file provisioner cannot connect, so instances would keep their cloud-init placeholders and backups would not run. Set TF_VAR_ssh_private_key."
  }
}

# =============================================================================
# WAZUH AGENT
# =============================================================================
# Endpoints, the CA fingerprint and the enrolment password are deliberately NOT
# defaulted here: this repository is public, and together they would map the
# SIEM. Set them in terraform.tfvars (gitignored). See the internal Wazuh agent
# enrolment runbook for the values.
#
# Enrolment and event reporting use TWO DIFFERENT hosts; they are not
# interchangeable and pointing at the wrong one fails as a silent timeout.

variable "wazuh_enabled" {
  description = "Enrol instances into the Wazuh SIEM."
  type        = bool
  default     = false
}

variable "wazuh_manager" {
  description = "Wazuh WORKERS address - receives agent events on 1514. NOT the enrolment host. Set in terraform.tfvars."
  type        = string
  default     = ""
}

variable "wazuh_registration_server" {
  description = "Wazuh MASTER address - handles enrolment on 1515. NOT the event host. Set in terraform.tfvars."
  type        = string
  default     = ""
}

variable "wazuh_registration_password" {
  description = "authd enrolment password. Held in 1Password; see the internal Wazuh agent enrolment runbook for the item reference."
  type        = string
  sensitive   = true
  default     = ""

  validation {
    condition     = var.wazuh_registration_password == "" || length(var.wazuh_registration_password) >= 16
    error_message = "Wazuh enrolment password must be at least 16 characters."
  }

  # A `check` block was used for this first. check blocks only WARN - plan and
  # apply both proceed - so enabling Wazuh with values missing would have
  # replaced every instance with cloud-init that could never enrol.
  # Cross-variable validation errors instead (Terraform >= 1.9; root requires 1.10).
  validation {
    condition = !var.wazuh_enabled || (
      var.wazuh_manager != "" &&
      var.wazuh_registration_server != "" &&
      var.wazuh_registration_password != "" &&
      var.wazuh_ca_sha256 != ""
    )
    error_message = "wazuh_enabled is true but one of wazuh_manager, wazuh_registration_server, wazuh_registration_password or wazuh_ca_sha256 is empty. Set them in terraform.tfvars; they are deliberately not defaulted in this public repository."
  }
}

variable "wazuh_agent_group" {
  description = "Comma-separated Wazuh agent groups. Groups must already exist on the manager."
  type        = string
  default     = "default"

  validation {
    condition     = can(regex("^[a-zA-Z0-9_.-]+(,[a-zA-Z0-9_.-]+)*$", var.wazuh_agent_group))
    error_message = "Agent groups must be a comma-separated list of alphanumeric names."
  }
}

variable "wazuh_ca_sha256" {
  description = "Expected SHA-256 fingerprint of the pinned Wazuh manager CA (colon-separated, uppercase). The agent refuses to enrol if the fetched CA does not match. Set in terraform.tfvars."
  type        = string
  default     = ""

  validation {
    condition     = var.wazuh_ca_sha256 == "" || can(regex("^([0-9A-F]{2}:){31}[0-9A-F]{2}$", var.wazuh_ca_sha256))
    error_message = "Must be a colon-separated uppercase SHA-256 fingerprint (32 bytes)."
  }
}

variable "wazuh_ca_object" {
  description = "Object key of the pinned manager CA within the primary backup bucket. Fetched at boot rather than embedded, because a 2.2KB PEM does not fit in user_data."
  type        = string
  default     = "_bootstrap/manager-ca.pem"
}

# =============================================================================
# CANONICAL LANDSCAPE (SaaS)
# =============================================================================

variable "landscape_enabled" {
  description = "Enrol instances into Canonical Landscape SaaS."
  type        = bool
  default     = false
}

variable "landscape_account_name" {
  description = "Landscape SaaS account name, from the Landscape web portal homepage."
  type        = string
  default     = ""

  validation {
    condition     = !var.landscape_enabled || var.landscape_account_name != ""
    error_message = "landscape_enabled is true but landscape_account_name is empty; landscape-config requires it and enrolment would fail on every instance."
  }
}

variable "landscape_registration_key" {
  description = "Landscape account-wide registration key. Without it, machines land in Pending Computers and need manual approval."
  type        = string
  sensitive   = true
  default     = ""
}

variable "landscape_tags" {
  description = "Extra Landscape tags. Letters, digits, hyphens and underscores only - no dots, spaces or commas."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for t in var.landscape_tags : can(regex("^[-_0-9a-zA-Z]+$", t))])
    error_message = "Landscape tags may contain only letters, digits, hyphens and underscores."
  }
}

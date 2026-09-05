# File structure:
# ├── main.tf           # Main configuration file
# ├── variables.tf      # Variable definitions
# ├── outputs.tf        # Output definitions
# ├── provider.tf       # Provider configuration
# ├── modules/
#     ├── linode/       # Linode instance module
#     │   ├── main.tf
#     │   ├── variables.tf
#     │   ├── outputs.tf
#     │   └── user_data.tftpl
#     └── volume/       # Volume module
#         ├── main.tf
#         ├── variables.tf
#         └── outputs.tf

# main.tf

# Generate a global unique suffix shared across all resources
# This ensures all VMs, firewalls, and related resources have the same identifier
resource "random_id" "global_suffix" {
  byte_length = 4

  keepers = {
    # Regenerate if project name changes
    project_name = var.project_name
  }
}

# =============================================================================
# DNS DOMAIN
# =============================================================================
# Domain is created/referenced here (not in DNS module) to break circular dependency:
# - ACME certificate needs domain to exist for DNS-01 challenge
# - DNS module needs instance IPs for A/AAAA records
# - Instances need ACME certificate for SSL

# Create new domain (if create_domain = true)
resource "linode_domain" "resilio" {
  count = var.create_domain ? 1 : 0

  type      = "master"
  domain    = var.tld
  soa_email = "admin@${var.tld}"
  tags      = ["terraform", "dns", var.project_name]

  # NOTE: this resource has count = var.create_domain ? 1 : 0, and create_domain
  # defaults to FALSE. When reusing an existing Linode zone this block never
  # applies, so that zone keeps Linode's 86400s SOA minimum and the negative
  # cache can outlast the ACME propagation timeout. Set the zone's TTL by hand
  # in that case - Terraform cannot do it through a data source.
  #
  # NOTE: this does NOT lower the SOA `minimum` field (the NEGATIVE cache TTL).
  # Tested: after applying ttl_sec = 300 the published SOA still reported
  # minimum=86400 for 10+ minutes, and a control zone that has never had
  # ttl_sec set reports the same 86400. Linode does not expose the SOA minimum.
  #
  # The consequence is a live renewal hazard: a resolver that queries
  # _acme-challenge before the record exists caches that miss for 24 HOURS,
  # which outlasts the 1200s propagation timeout. Renewal always queries a name
  # that does not yet exist.
  #
  # Mitigation when renewing manually: pre-create a dummy TXT at
  # _acme-challenge first, so resolvers cache a positive answer instead of an
  # NXDOMAIN. lego appends rather than replaces and matches its own value among
  # all answers, so the dummy is harmless and can be removed afterwards.
  #
  # ttl_sec is kept because it does set the default record TTL, which is useful
  # in its own right - just not for the SOA minimum.
  ttl_sec = 300

  lifecycle {
    prevent_destroy = true
  }
}

# Use existing domain (if create_domain = false)
data "linode_domain" "existing" {
  count = var.create_domain ? 0 : 1

  domain = var.tld
}

# Local for domain ID
locals {
  domain_id = var.create_domain ? linode_domain.resilio[0].id : data.linode_domain.existing[0].id
}

# =============================================================================
# CAA - authorise Let's Encrypt for this subtree, including wildcards
# =============================================================================
# A CA climbs from the requested name toward the root and uses the FIRST
# non-empty CAA RRset (RFC 8659 sec.3). Publishing one at this zone apex
# therefore takes precedence over whatever the parent zone publishes - and
# REPLACES it for this subtree, so both tags must be present or non-wildcard
# issuance breaks too.
#
# This matters because RFC 8659 sec.4.3 says a wildcard request considers
# `issuewild` INSTEAD of `issue`. A parent publishing `issuewild ";"` (which
# authorises nobody) silently blocks *.<tld> even when `issue` permits the CA -
# and the failure surfaces only at issuance, as urn:ietf:params:acme:error:caa.
# Pinning the policy here makes this subtree independent of the parent zone,
# which may be managed by a different team or provider.
resource "linode_domain_record" "caa_issue" {
  domain_id   = local.domain_id
  name        = ""
  record_type = "CAA"
  tag         = "issue"
  target      = "letsencrypt.org"
}

resource "linode_domain_record" "caa_issuewild" {
  domain_id   = local.domain_id
  name        = ""
  record_type = "CAA"
  tag         = "issuewild"
  target      = "letsencrypt.org"
}

# =============================================================================
# ACME / LET'S ENCRYPT SSL CERTIFICATES
# =============================================================================

# Version trigger for ACME account key rotation.
#
# Bump this whenever the Let's Encrypt account behind the current key has been
# deactivated. Deactivation is PERMANENT and irreversible: LE then refuses
# new-acct for that public key forever with
#   403 urn:ietf:params:acme:error:unauthorized
#   "An account with the provided public key exists but is deactivated"
# and the only way forward is a fresh account key, which is what bumping this
# produces via replace_triggered_by on tls_private_key.acme_account.
#
# NOTE: destroying acme_registration DEACTIVATES the account as its delete
# operation. So any `terraform destroy`, `-replace`, or a change to an argument
# that forces replacement (email is derived from var.tld, so changing the
# domain does it) burns the account key and requires a bump here.
# !! CHANGING THIS VALUE REPLACES EVERY INSTANCE. Apply it targeted, then roll
#    regions one at a time. Never as part of an ordinary `terraform apply`.
#
#    account_key_pem is ForceNew on acme_certificate, so a bump replaces the key,
#    the registration and the certificate. The new PEMs flow into every
#    linode_instances module and are interpolated into metadata.user_data, which
#    is also force-new and is NOT in ignore_changes. create_before_destroy is
#    off, so all regions are destroyed CONCURRENTLY.
#
#    min_days_remaining = -1 does NOT protect against this: it only short-circuits
#    the renewal path, while schema-level ForceNew is evaluated separately.
#
#    Correct procedure:
#      # CAA first: if the parent zone blocks Let's Encrypt, issuance fails
#      # unless these exist beforehand.
#      terraform apply -target=linode_domain.resilio \
#                      -target=linode_domain_record.caa_issue \
#                      -target=linode_domain_record.caa_issuewild
#      terraform apply -target=terraform_data.acme_key_version \
#                      -target=tls_private_key.acme_account \
#                      -target=acme_registration.resilio \
#                      -target=acme_certificate.resilio
#      # then, per region, waiting for each to resync:
#      terraform apply -target='module.linode_instances["<region>"]'
#
#    The durable fix is to stop putting the PEMs in user_data and deliver them
#    via null_resource.provision_scripts (which has a content-hash trigger since
#    #53), so a certificate change re-provisions files instead of replacing hosts.
resource "terraform_data" "acme_key_version" {
  input = "3" # Bumped after the previous account was deactivated. See warning above.
}

# ACME provider registration for Let's Encrypt
resource "tls_private_key" "acme_account" {
  algorithm = "RSA"
  rsa_bits  = 4096

  lifecycle {
    replace_triggered_by = [terraform_data.acme_key_version]
  }
}

resource "acme_registration" "resilio" {
  account_key_pem = tls_private_key.acme_account.private_key_pem
  email_address   = "admin@${var.tld}"
}

# Let's Encrypt wildcard certificate for all Resilio instances
# Note: Wildcard covers all subdomains, so per-region SANs are not needed
resource "acme_certificate" "resilio" {
  account_key_pem = acme_registration.resilio.account_key_pem
  common_name     = var.dns_include_project_name ? "${var.project_name}.${var.tld}" : var.tld
  subject_alternative_names = var.dns_include_project_name ? [
    "*.${var.project_name}.${var.tld}"
    ] : [
    "*.${var.tld}"
  ]

  # lego v5 (provider 3.x, bumped from 2.48.3) turned the RECURSIVE nameserver
  # propagation check ON by default; under lego v4 it was opt-in and never ran.
  # checkNameserversPropagationCustom returns on the FIRST nameserver that
  # errors, and it reads /etc/resolv.conf. If ANY resolver listed there fails to
  # answer for this zone - a stale DHCP-supplied entry is the common case - the
  # recursive stage fails on every poll, forever, and the authoritative stage,
  # which would have passed, is never reached.
  #
  # It is silent by construction: wait.For keeps the error in lastErr and logs
  # it at Debug, and the provider's log bridge drops slog attributes, so even
  # TF_LOG=DEBUG shows only "lego: Waiting for condition failed." The apply just
  # sits in "Still modifying..." for 2x the propagation timeout (once per
  # authorization: apex and wildcard).
  #
  # Pin resolvers that actually answer rather than inheriting resolv.conf. Keep
  # this list SHORT - every entry must succeed, so each one is another way to
  # fail. Fix the router's DHCP typo too, but this is the durable fix: it also
  # covers CI runners and any other machine on that network.
  recursive_nameservers = ["1.1.1.1:53", "1.0.0.1:53"]

  # Do NOT revoke on destroy. Replacement destroys before creating, so the
  # default would revoke the certificate the instances are currently serving,
  # before its replacement exists - and revocation cannot be undone. A
  # superseded certificate expiring naturally is the safer failure mode.
  revoke_certificate_on_destroy = false

  dns_challenge {
    provider = "linode"
    config = {
      LINODE_TOKEN = var.linode_token
      # Measured: a new TXT is live on all five authoritative Linode nameservers
      # ~146s after the API create returns. 1200s is ~8x headroom. Raising this
      # to 3600 during the incident was treating the wrong symptom - the hang
      # was the recursive-NS check above, not propagation latency - and it only
      # made each failure take twice as long.
      LINODE_PROPAGATION_TIMEOUT = "1200" # 20 min; measured need is ~150s
      LINODE_POLLING_INTERVAL    = "30"   # Check every 30 seconds
      LINODE_TTL                 = "300"  # 5 minute TTL (Linode minimum)
    }
  }

  # DELIBERATELY -1: automatic renewal is UNSAFE with the current architecture.
  #
  # certificate_pem / private_key_pem / issuer_pem feed every instance through
  # ssl_certificate / ssl_private_key / ssl_issuer_cert (main.tf ~350), which
  # the module interpolates into metadata.user_data. metadata is force-new and
  # is NOT in ignore_changes (the lifecycle block in modules/linode/main.tf is
  # comments only), and create_before_destroy was deliberately removed because
  # Linode requires unique labels. Instances use for_each over var.regions.
  #
  # So an automatic renewal would destroy EVERY region in parallel, unattended,
  # with no operator present - a full-service outage triggered by a background
  # timer. Setting this to 30 arms exactly that.
  #
  # Until certificate delivery is decoupled from user_data (deliver the PEMs via
  # null_resource.provision_scripts, which now has a content hash trigger, so a
  # renewal re-provisions files instead of replacing hosts), renewal must stay
  # manual and staged one region at a time.
  #
  # Current certificate expires 2026-12-04. Renew before then with:
  #   terraform apply -replace=acme_certificate.resilio -target=acme_certificate.resilio
  #
  # NOTE: -replace destroys before creating, and the provider REVOKES on destroy
  # by default - so the live certificate would be revoked while the instances are
  # still serving it, and revocation is irreversible. revoke_certificate_on_destroy
  # is set to false below for exactly this reason; the superseded certificate is
  # left to expire naturally instead. Revoke deliberately, and only on suspected
  # key compromise.
  # then roll regions individually per CLAUDE.md.
  min_days_remaining = -1
}

# Create per-folder data volumes for each region
# Each folder in resilio_folders gets its own independent volume
module "storage_volumes" {
  source = "./modules/volume"

  for_each = toset(var.regions) # ["us-east", "eu-west"]

  region       = each.key
  folders      = var.resilio_folders # Map of folder names to {key, size}
  project_name = var.project_name
  tags         = local.tags # Concat tags and tld
}

# =============================================================================
# BACKUP OBJECT STORAGE
# =============================================================================

# Create and manage Object Storage buckets for backups
# Note: Buckets are created when backup_storage_regions is non-empty, regardless of backup_enabled.
# This prevents accidental bucket destruction when toggling backup_enabled.
# The backup_enabled variable only controls whether backup scripts run on instances.
module "backup_storage" {
  source = "./modules/object-storage"
  count  = length(var.backup_storage_regions) > 0 ? 1 : 0

  project_name   = var.project_name
  suffix         = random_id.global_suffix.hex
  bucket_prefix  = var.backup_bucket_prefix
  backup_regions = var.backup_storage_regions

  enable_versioning = var.backup_versioning
  retention_days    = var.backup_retention_days
  tags              = local.tags
}

# Local values for backup configuration
# Handles both Terraform-managed (backup_enabled=true) and legacy manual configuration
locals {
  # Determine effective backup configuration
  backup_access_key = var.backup_enabled ? (
    length(module.backup_storage) > 0 ? module.backup_storage[0].access_key : ""
  ) : var.object_storage_access_key

  backup_secret_key = var.backup_enabled ? (
    length(module.backup_storage) > 0 ? module.backup_storage[0].secret_key : ""
  ) : var.object_storage_secret_key

  backup_buckets = var.backup_enabled ? (
    length(module.backup_storage) > 0 ? module.backup_storage[0].buckets : {}
  ) : {}

  backup_primary_endpoint = var.backup_enabled ? (
    length(module.backup_storage) > 0 ? module.backup_storage[0].primary_endpoint : ""
  ) : var.object_storage_endpoint

  backup_primary_bucket = var.backup_enabled ? (
    length(module.backup_storage) > 0 ? module.backup_storage[0].primary_bucket.name : ""
  ) : var.object_storage_bucket

  # Determine which regions should run backups
  # Use new variable if set, fall back to legacy variable
  effective_backup_source_regions = length(var.backup_source_regions) > 0 ? var.backup_source_regions : var.backup_regions

  # Backup configuration to pass to instances
  backup_config = {
    enabled          = var.backup_enabled || var.object_storage_access_key != "CHANGEME"
    mode             = var.backup_mode
    schedule         = var.backup_schedule
    transfers        = var.backup_transfers
    bandwidth_limit  = var.backup_bandwidth_limit
    versioning       = var.backup_versioning
    retention_days   = var.backup_retention_days
    access_key       = local.backup_access_key
    secret_key       = local.backup_secret_key
    primary_endpoint = local.backup_primary_endpoint
    primary_bucket   = local.backup_primary_bucket
    all_buckets      = local.backup_buckets
  }
}

# =============================================================================
# FIREWALLS
# =============================================================================

# Create separate firewalls for jumpbox and resilio instances
# Jumpbox firewall - allows SSH from external network
module "jumpbox_firewall" {
  source = "./modules/jumpbox-firewall"

  project_name = var.project_name
  suffix       = random_id.global_suffix.hex # Use global suffix
  # Use auto-detected IP if allowed_ssh_cidr is not specified
  allowed_ssh_cidr = var.allowed_ssh_cidr != null ? var.allowed_ssh_cidr : local.current_ip_cidr
  tags             = local.tags # Concat tags and tld
}

# Resilio firewall - allows SSH from jumpbox and inter-instance communication
# Created with empty rules initially to avoid circular dependency
module "resilio_firewall" {
  source = "./modules/resilio-firewall"

  # Start with empty IPs - rules will be added via terraform_data resource below
  linode_ipv4  = []
  linode_ipv6  = []
  jumpbox_ipv4 = null
  jumpbox_ipv6 = null

  project_name = var.project_name
  suffix       = random_id.global_suffix.hex # Use global suffix
  tags         = local.tags                  # Concat tags and tld
}

# Create jumpbox instance (bastion host for secure access)
module "jumpbox" {
  source = "./modules/jumpbox"

  region         = var.jumpbox_region
  instance_type  = var.jumpbox_instance_type
  ssh_public_key = var.ssh_public_key
  project_name   = var.project_name
  suffix         = random_id.global_suffix.hex # Use global suffix
  firewall_id    = module.jumpbox_firewall.firewall_id
  tags           = local.tags
  cloud_user     = var.cloud_user
}

module "linode_instances" {
  source = "./modules/linode"

  for_each = toset(var.regions)

  region         = each.key          # "us-east"
  instance_type  = var.instance_type # "g6-standard-2"
  ssh_public_key = var.ssh_public_key
  project_name   = var.project_name            # "resilio-sync"
  suffix         = random_id.global_suffix.hex # Use global suffix

  include_project_name_in_hostname = var.dns_include_project_name

  # Per-folder volume configuration (new)
  resilio_folders = var.resilio_folders                      # Map of folder names to {key, size}
  folder_volumes  = module.storage_volumes[each.key].volumes # Map of folder names to volume details

  # Deprecated - kept for backward compatibility
  resilio_folder_keys = var.resilio_folder_keys
  resilio_folder_key  = var.resilio_folder_key
  volume_id           = module.storage_volumes[each.key].volume_id

  resilio_license_key    = var.resilio_license_key
  ubuntu_advantage_token = var.ubuntu_advantage_token
  tld                    = var.tld

  firewall_id = module.resilio_firewall.firewall_id # Attach resilio firewall during creation

  # SSL certificate from Let's Encrypt
  ssl_certificate = acme_certificate.resilio.certificate_pem
  ssl_private_key = acme_certificate.resilio.private_key_pem
  ssl_issuer_cert = acme_certificate.resilio.issuer_pem

  # Backup configuration (Terraform-managed or legacy)
  backup_config = {
    enabled          = local.backup_config.enabled && contains(local.effective_backup_source_regions, each.key)
    mode             = local.backup_config.mode
    schedule         = local.backup_config.schedule
    transfers        = local.backup_config.transfers
    bandwidth_limit  = local.backup_config.bandwidth_limit
    versioning       = local.backup_config.versioning
    retention_days   = local.backup_config.retention_days
    access_key       = local.backup_config.access_key
    secret_key       = local.backup_config.secret_key
    primary_endpoint = local.backup_config.primary_endpoint
    primary_bucket   = local.backup_config.primary_bucket
    all_buckets      = local.backup_config.all_buckets
  }

  # Legacy variables (deprecated, kept for compatibility)
  object_storage_access_key = local.backup_access_key
  object_storage_secret_key = local.backup_secret_key
  object_storage_endpoint   = local.backup_primary_endpoint
  object_storage_bucket     = local.backup_primary_bucket
  enable_backup             = local.backup_config.enabled && contains(local.effective_backup_source_regions, each.key)

  # Wazuh agent enrolment.
  # NOTE: manager and registration_server are DIFFERENT hosts by design -
  # events go to the workers on 1514, enrolment to the master on 1515.
  wazuh_config = {
    enabled               = var.wazuh_enabled
    manager               = var.wazuh_manager
    registration_server   = var.wazuh_registration_server
    registration_password = var.wazuh_registration_password
    agent_group           = var.wazuh_agent_group
    ca_sha256             = var.wazuh_ca_sha256
    ca_object             = var.wazuh_ca_object
  }

  # Canonical Landscape SaaS enrolment.
  landscape_config = {
    enabled          = var.landscape_enabled
    account_name     = var.landscape_account_name
    registration_key = var.landscape_registration_key
    tags = join(",", concat(
      ["resilio", replace(var.project_name, ".", "-")],
      [replace(each.key, ".", "-")],
      var.landscape_tags,
    ))
  }

  # Phase-2 script delivery. Without these the instance keeps the cloud-init
  # placeholders and backups silently do nothing.
  provision_scripts = var.provision_scripts
  ssh_private_key   = var.ssh_private_key
  jumpbox_ip        = local.jumpbox_ip

  tags       = local.tags # Concat tags and tld
  cloud_user = var.cloud_user
}

module "dns" {
  source = "./modules/dns"

  # Domain ID from domain created/referenced above
  domain_id = local.domain_id

  # Map of DNS records keyed by region (static, known at plan time)
  dns_records = {
    for region, inst in module.linode_instances : region => {
      ipv4 = one(inst.ipv4_address) # Extract single IP from set
      ipv6 = inst.ipv6_address      # Already a string
    }
  }

  project_name         = var.project_name
  include_project_name = var.dns_include_project_name
}

# Local values for firewall rule updates
locals {
  jumpbox_ip           = module.jumpbox.ipv4_address
  resilio_instance_ips = [for inst in module.linode_instances : tolist(inst.ipv4_address)[0]]
  resilio_firewall_id  = module.resilio_firewall.firewall_id
}

# Update resilio firewall rules after instances are created
# This uses terraform_data (modern replacement for null_resource)
resource "terraform_data" "update_resilio_firewall" {
  # Trigger update whenever IPs or firewall ID changes
  # Bump version to force re-execution if needed
  triggers_replace = {
    version      = "3" # Increment this to force firewall rules update
    jumpbox_ip   = local.jumpbox_ip
    instance_ips = join(",", local.resilio_instance_ips)
    firewall_id  = local.resilio_firewall_id
  }

  # Update firewall rules using Linode API
  provisioner "local-exec" {
    command = <<-EOT
      set -e

      echo "Updating resilio firewall rules..."

      # Prepare variables
      FIREWALL_ID="${local.resilio_firewall_id}"
      JUMPBOX_IP="${local.jumpbox_ip}"
      INSTANCE_IPS='${jsonencode(local.resilio_instance_ips)}'

      # Validate that we have the required IPs
      if [ -z "$JUMPBOX_IP" ]; then
        echo "❌ ERROR: Jumpbox IP is empty. Cannot update firewall rules."
        exit 1
      fi

      if [ "$INSTANCE_IPS" = "[]" ] || [ -z "$INSTANCE_IPS" ]; then
        echo "❌ ERROR: No Resilio instance IPs found. Cannot update firewall rules."
        echo "   This usually means the Resilio instances haven't been created yet."
        exit 1
      fi

      echo "📋 Firewall update details:"
      echo "   Firewall ID: $FIREWALL_ID"
      echo "   Jumpbox IP: $JUMPBOX_IP"
      echo "   Instance IPs: $(echo $INSTANCE_IPS | jq -r '.[]' | tr '\n' ' ')"
      echo ""

      # Create rules JSON
      cat > /tmp/resilio-fw-$${FIREWALL_ID}.json <<RULES_EOF
{
  "inbound": [
    {
      "label": "jumpbox-to-resilio-ssh",
      "action": "ACCEPT",
      "protocol": "TCP",
      "ports": "22,2022",
      "addresses": {
        "ipv4": ["$${JUMPBOX_IP}/32"]
      }
    },
    {
      "label": "jumpbox-to-resilio-webui",
      "action": "ACCEPT",
      "protocol": "TCP",
      "ports": "8888",
      "addresses": {
        "ipv4": ["$${JUMPBOX_IP}/32"]
      }
    },
    {
      "label": "external-to-resilio-webui",
      "action": "ACCEPT",
      "protocol": "TCP",
      "ports": "8888,8889",
      "addresses": {
        "ipv4": ["${var.allowed_webui_cidr != null ? var.allowed_webui_cidr : local.current_ip_cidr}"]
      }
    },
    {
      "label": "jumpbox-to-resilio-ping",
      "action": "ACCEPT",
      "protocol": "ICMP",
      "addresses": {
        "ipv4": ["$${JUMPBOX_IP}/32"]
      }
    },
    {
      "label": "resilio-all-tcp",
      "action": "ACCEPT",
      "protocol": "TCP",
      "addresses": {
        "ipv4": $(echo $${INSTANCE_IPS} | jq '[.[] | . + "/32"]')
      }
    },
    {
      "label": "resilio-all-udp",
      "action": "ACCEPT",
      "protocol": "UDP",
      "addresses": {
        "ipv4": $(echo $${INSTANCE_IPS} | jq '[.[] | . + "/32"]')
      }
    },
    {
      "label": "resilio-all-icmp",
      "action": "ACCEPT",
      "protocol": "ICMP",
      "addresses": {
        "ipv4": $(echo $${INSTANCE_IPS} | jq '[.[] | . + "/32"]')
      }
    }
  ],
  "inbound_policy": "DROP",
  "outbound_policy": "ACCEPT"
}
RULES_EOF

      # Update firewall
      echo "🔧 Calling Linode API to update firewall $${FIREWALL_ID}..."
      RESPONSE=$(curl -s -w "\n%%{http_code}" -X PUT \
        -H "Authorization: Bearer ${var.linode_token}" \
        -H "Content-Type: application/json" \
        -d @/tmp/resilio-fw-$${FIREWALL_ID}.json \
        "https://api.linode.com/v4/networking/firewalls/$${FIREWALL_ID}/rules")

      HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
      BODY=$(echo "$RESPONSE" | sed '$d')

      # Check response
      if [ "$HTTP_CODE" -eq 200 ]; then
        echo "✅ Resilio firewall rules updated successfully!"
        echo ""
        echo "Applied rules:"
        echo "   • Allow SSH (ports 22, 2022) from jumpbox: $${JUMPBOX_IP}"
        echo "   • Allow HTTPS Web UI (port 8888) from jumpbox: $${JUMPBOX_IP}"
        echo "   • Allow HTTPS Web UI (ports 8888, 8889) from external: ${var.allowed_webui_cidr != null ? var.allowed_webui_cidr : local.current_ip_cidr}"
        echo "   • Allow ICMP from jumpbox: $${JUMPBOX_IP}"
        echo "   • Allow all TCP traffic between Resilio instances"
        echo "   • Allow all UDP traffic between Resilio instances"
        echo "   • Allow ICMP between Resilio instances"
        echo "   • Instance IPs: $(echo $${INSTANCE_IPS} | jq -r '.[]' | tr '\n' ' ')"
        echo ""
        echo "Firewall ID: $${FIREWALL_ID}"
      else
        echo "❌ Failed to update firewall rules (HTTP $${HTTP_CODE})"
        echo ""
        echo "API Response:"
        echo "$BODY" | jq '.' 2>/dev/null || echo "$BODY"
        echo ""
        echo "Generated rules file saved at: /tmp/resilio-fw-$${FIREWALL_ID}.json"
        echo "You can inspect it for debugging or apply manually with:"
        echo "  curl -X PUT -H 'Authorization: Bearer \$LINODE_TOKEN' \\"
        echo "       -H 'Content-Type: application/json' \\"
        echo "       -d @/tmp/resilio-fw-$${FIREWALL_ID}.json \\"
        echo "       https://api.linode.com/v4/networking/firewalls/$${FIREWALL_ID}/rules"
        exit 1
      fi

      # Clean up
      rm -f /tmp/resilio-fw-$${FIREWALL_ID}.json
    EOT

    interpreter = ["bash", "-c"]
  }

  # Ensure instances are created before updating firewall
  depends_on = [
    module.jumpbox,
    module.linode_instances,
    module.resilio_firewall
  ]
}

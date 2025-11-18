# .tflint.hcl
# TFLint configuration for Terraform code linting
# Documentation: https://github.com/terraform-linters/tflint

config {
  # Enable module inspection
  module = true

  # Force the behavior of returning an error code when issues are found
  force = false

  # Disable color output
  disabled_by_default = false
}

# Enable Terraform plugin
plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Enable Linode provider plugin (if available)
# plugin "linode" {
#   enabled = true
#   version = "0.1.0"
#   source  = "github.com/terraform-linters/tflint-ruleset-linode"
# }

# Rule configurations
rule "terraform_deprecated_interpolation" {
  enabled = true
}

rule "terraform_deprecated_index" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_comment_syntax" {
  enabled = true
}

rule "terraform_documented_outputs" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_module_pinned_source" {
  enabled = true
  style   = "semver"  # or "flexible"
}

rule "terraform_naming_convention" {
  enabled = true

  # Variable naming
  variable {
    format = "snake_case"
  }

  # Local naming
  locals {
    format = "snake_case"
  }

  # Output naming
  output {
    format = "snake_case"
  }

  # Resource naming
  resource {
    format = "snake_case"
  }

  # Module naming
  module {
    format = "snake_case"
  }

  # Data source naming
  data {
    format = "snake_case"
  }
}

rule "terraform_required_version" {
  enabled = true
}

rule "terraform_required_providers" {
  enabled = true
}

rule "terraform_standard_module_structure" {
  enabled = true
}

rule "terraform_workspace_remote" {
  enabled = true
}

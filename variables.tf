# Organization Variables
variable "organization_name" {
  description = "The name of the TFE organization"
  type        = string
}

variable "organization_email" {
  description = "Admin email address for the organization"
  type        = string
}

variable "tfe_token" {
  description = "TFE API token for authentication"
  type        = string
  sensitive   = true
  default     = null
}

variable "tfe_hostname" {
  description = "TFE hostname for authentication"
  type        = string
  sensitive   = true
  default     = null
}

variable "tfe_management_project_name" {
  description = "Name of the management project"
  type        = string
  default     = "tfe-management"
}

variable "tfe_management_workspace_name" {
  description = "Name of the management workspace"
  type        = string
  default     = "tfe-management"
}

# VCS Configuration
variable "vcs_oauth_token_id" {
  description = "OAuth token id for VCS integration. For ADO VCS, this should be created in TFE and the ID should be provided here."
  type        = string
  sensitive   = true
  default     = "mock-up-value"
}

variable "vcs_https_url" {
  description = "VCS HTTPS URL (e.g., https://dev.azure.com/organization)"
  type        = string
}

variable "vcs_api_url" {
  description = "Azure DevOps API URL (e.g., https://dev.azure.com/organization)"
  type        = string
}

variable "vcs_organization" {
  description = "Azure DevOps organization name"
  type        = string
}

variable "vcs_project" {
  description = "Azure DevOps project name"
  type        = string
}

variable "vcs_repository_management" {
  description = "Azure DevOps repository name for tfe-management configuration"
  type        = string
}

variable "vcs_repository_private_registry" {
  description = "Azure DevOps repository name for tfe-private-registry configuration"
  type        = string
}

# Workspace Configuration
variable "vcs_branch_management" {
  description = "VCS branch to track for the management workspace"
  type        = string
  default     = "main"
}

variable "vcs_branch_private_registry" {
  description = "VCS branch to track for the private registry workspace"
  type        = string
  default     = "main"
}

variable "terraform_version" {
  description = "Terraform version to use in the workspace"
  type        = string
  default     = "1.5.0"
}

variable "auto_apply" {
  description = "Whether to automatically apply changes when a plan succeeds"
  type        = bool
  default     = false
}

variable "working_directory" {
  description = "Working directory for Terraform runs in the workspace"
  type        = string
  default     = ""
}

# Notification Configuration (Optional)
variable "notification_configurations" {
  description = "Map of notification configurations for the bootstrap workspace"
  type = map(object({
    destination_type = string
    enabled          = optional(bool, true)
    url              = optional(string)
    token            = optional(string)
    triggers         = optional(list(string))
    email_user_ids   = optional(list(string))
    email_addresses  = optional(list(string))
  }))
  default = {}
}

variable "smtp_username" {
  description = "SMTP username used when notifications are enabled for emails. Defaults to 'null'"
  type        = string
  default     = null
}

variable "smtp_test_email_address" {
  description = "Email address to test SMTP notifications after set up. Defaults to 'null'"
  type        = string
  default     = null
}

# SSH Key for Git Access Configuration
variable "ssh_private_key" {
  description = "Private SSH key for Git access to the Azure DevOps repository"
  type        = string
  sensitive   = true
}

# Dynamic credentials Azure configuration
variable "azure_subscriptions" {
  description = "Map of Azure subscriptions to configure dynamic credentials for. The map key is used as the provider alias and as the TAG suffix in TFC_AZURE_* environment variables (uppercased)."
  type = map(object({
    subscription_id = string
    tenant_id       = string
  }))
}

variable "add_bootstrap_user_ownership" {
  description = "Whether to explicitly manage the bootstrap user as an application owner. Set to false in tenants where the creator is automatically added as owner (e.g. delegated/user-context creation), to avoid an 'already exists' error. Set to true in tenants/auth contexts where auto-assignment does not occur (e.g. app-only/service-principal creation)."
  type        = bool
  default     = true
}

# General Azure configuration
variable "resource_group_name" {
  type        = string
  description = "Azure Resource Group name where resources will be created"
}

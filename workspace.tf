# Management Workspace
module "management_workspace" {
  # source = "../../workspace"
  source = "git@github.com:permilche/tfe-tf-modules.git//workspace?ref=main" # cannot use variables there so need to hardcode it

  organization = var.organization_name
  name         = var.tfe_management_workspace_name
  description  = "Workspace for managing TFE organization configuration"
  project_id   = module.management_project.id

  # VCS Configuration pointing to Azure DevOps (using automatic identifier construction)
  vcs_repo = {
    vcs_provider     = "azure_devops"
    vcs_organization = var.vcs_organization
    vcs_project      = var.vcs_project
    repository       = var.vcs_repository_management
    branch           = var.vcs_branch_management
    oauth_token_id   = var.vcs_oauth_token_id
  }

  # Workspace settings
  terraform_version     = var.terraform_version
  auto_apply            = var.auto_apply
  queue_all_runs        = false
  file_triggers_enabled = true
  working_directory     = var.working_directory

  # Execution mode
  execution_mode = "remote"

  # Variables for the management workspace
  variables = {
    organization = {
      value       = var.organization_name
      category    = "terraform"
      description = "TFE organization name"
    }
    tfe_token = {
      value       = var.tfe_token
      category    = "terraform"
      sensitive   = true
      description = "TFE API token for workspace operations"
    }
    tfe_hostname = {
      value       = var.tfe_hostname
      category    = "terraform"
      sensitive   = true
      description = "TFE hostname for workspace operations"
    }
    vcs_org = {
      value       = var.vcs_organization
      category    = "terraform"
      description = "Azure DevOps organization name"
    }
    vcs_oauth_token_id = {
      value       = var.vcs_oauth_token_id
      category    = "terraform"
      description = "OAuth token id for VCS integration"
    }
    vcs_project = {
      value       = var.vcs_project
      category    = "terraform"
      description = "Azure DevOps project name. Used to create the workspaces afterwards"
    }
    # need it here to inject them in the managed projects/workspaces created from this workspace (tfe-management)
    az_subscription_id = {
      value       = var.az_subscription_id
      category    = "terraform"
      description = "Azure subscription ID"
    }
    az_tenant_id = {
      value       = var.az_tenant_id
      category    = "terraform"
      description = "Azure tenant ID"
    }
    az_client_id = {
      category  = "terraform"
      value     = var.az_client_id
    }
    az_client_secret = {
      category  = "terraform"
      value     = var.az_client_secret
      sensitive = true
    }
  }
  
  # Notification configuration (optional)
  notification_configurations = var.notification_configurations
  
  depends_on = [module.organization_settings]
}

# Private Registry Workspace
module "private_registry_workspace" {
  # source = "../../workspace"
  source = "git@github.com:permilche/tfe-tf-modules.git//workspace?ref=main" # cannot use variables there so need to hardcode it

  organization = var.organization_name
  name         = "tfe-private-registry"
  description  = "Workspace for managing TFE organization Private Registry configuration"
  project_id   = module.management_project.id

  # VCS Configuration pointing to Azure DevOps (using automatic identifier construction)
  vcs_repo = {
    vcs_provider     = "azure_devops"
    vcs_organization = var.vcs_organization
    vcs_project      = var.vcs_project
    repository       = var.vcs_repository_private_registry
    branch           = var.vcs_branch_private_registry
    oauth_token_id   = var.vcs_oauth_token_id
  }

  # Workspace settings
  terraform_version     = var.terraform_version
  auto_apply            = var.auto_apply
  queue_all_runs        = false
  file_triggers_enabled = true
  working_directory     = var.working_directory

  # Execution mode
  execution_mode = "remote"

  # Variables for the private-registry workspace
  variables = {
      organization = {
      value       = var.organization_name
      category    = "terraform"
      description = "TFE organization name"
    }
    tfe_token = {
      value       = var.tfe_token
      category    = "terraform"
      sensitive   = true
      description = "TFE API token for workspace operations"
    }
    tfe_hostname = {
      value       = var.tfe_hostname
      category    = "terraform"
      description = "TFE hostname for workspace operations"
    }
    vcs_oauth_token_id = {
      value       = var.vcs_oauth_token_id
      category    = "terraform"
      description = "OAuth token id for VCS integration"
    }
  }
  
  # Notification configuration (optional)
  notification_configurations = var.notification_configurations

  ssh_key_id = module.ssh_key.id
  
  depends_on = [module.organization_settings]
}

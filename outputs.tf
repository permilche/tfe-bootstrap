# Organization Outputs
output "organization_name" {
  description = "The name of the TFE organization"
  value       = var.organization_name
}

# VCS OAuth Outputs
# output "vcs_oauth_token_id" {
#   description = "The OAuth token ID for Azure DevOps VCS integration"
#   value       = module.vcs_azure_devops.oauth_token_id
# }

# output "vcs_oauth_client_id" {
#   description = "The OAuth client ID for Azure DevOps"
#   value       = module.vcs_azure_devops.oauth_client_id
# }

# Project Outputs
output "management_project_id" {
  description = "The ID of the management project"
  value       = module.management_project.id
}

output "management_project_name" {
  description = "The name of the management project"
  value       = module.management_project.name
}

# Workspace Outputs
output "management_workspace_id" {
  description = "The ID of the management workspace"
  value       = module.management_workspace.id
}

output "management_workspace_name" {
  description = "The name of the management workspace"
  value       = module.management_workspace.name
}

output "management_workspace_html_url" {
  description = "The URL to access the management workspace in TFE"
  value       = module.management_workspace.html_url
}

output "private_registry_workspace_id" {
  description = "The ID of the private registry workspace"
  value       = module.private_registry_workspace.id
}

output "private_registry_workspace_name" {
  description = "The name of the private registry workspace"
  value       = module.private_registry_workspace.name
}

output "private_registry_workspace_html_url" {
  description = "The URL to access the private registry workspace in TFE"
  value       = module.private_registry_workspace.html_url
}

# Azure Credentials Outputs
output "dynamic_credentials_azure_client_id" {
  description = "The client ID of the Azure AD application for dynamic credentials"
  value       = module.dynamic_credentials_azure_configuration.tfc_application_client_id
}

# ACS info
output "email_communication_service" {
  description = "The resource of email communication service"
  value       = module.avm-res-communication-emailservice.resource
}

output "email_communication_service_id" {
  description = "The resource ID of email communication service"
  value       = module.avm-res-communication-emailservice.resource_id
}

output "email_communication_service_in_azurerm_schema" {
  description = "The resource of email communication service in azurerm schema"
  value       = module.avm-res-communication-emailservice.resource_in_azurerm_schema
}

# Instructions for next steps
output "zz_next_steps" {
  description = "Instructions for using the management workspace"
  value = <<-EOT
    Management layer created successfully!
    
    P.S. Added "zz" at the beginning of the output name for the only purpose of showing last
    
    Next steps:
    1. Push this configuration to your VCS repository (remember this module is intended to be ran once and forget about it afterwards, but it should always be backed up in your VCS repository)
    2. The management workspace will automatically trigger runs on VCS changes
    3. Use the management workspace to manage all other TFE modules and resources from now on
    4. Access the workspace at: ${module.management_workspace.html_url}
    
    The management workspace is configured to use VCS workflow.
    All future TFE configuration should be managed through this workspace.
  EOT
}

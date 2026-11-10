# VCS OAuth Configuration. With the tfe provider version used here (0.79.0), the OAuth client cannot be created for Azure DevOps with this resource, so the OAuth token ID is created manually in TFE (it can be retrieved from the TFE UI or API) and passed to the workspace module. Newer provider versions add Azure DevOps support (check the provider changelog), so with one of them you can uncomment the module below and manage the connection as code.
# module "vcs_azure_devops" {
#   source = "../../vcs-oauth"
#   source = "git@github.com:permilche/tfe-tf-modules.git//vcs-oauth?ref=main" # cannot use variables there so need to hardcode it

#   organization     = var.organization_name
#   service_provider = "ado_server"
#   name             = "Azure DevOps"

#   # Azure DevOps OAuth configuration
#   oauth_token      = var.ado_oauth_token
#   http_url         = var.ado_http_url
#   api_url          = var.ado_api_url

#   depends_on = [module.organization_settings]
# }

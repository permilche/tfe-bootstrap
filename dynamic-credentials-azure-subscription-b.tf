provider "azurerm" {
  alias           = "subscription-b"
  subscription_id = var.azure_subscriptions["subscription-b"].subscription_id
  features {}
}

module "dynamic_credentials_azure_configuration_subscription_b" {
  source = "git@github.com:permilche/tfe-tf-modules.git//dynamic-credentials/azure/configuration?ref=main" # cannot use variables there so need to hardcode it

  providers = {
    azurerm = azurerm.subscription-b
  }

  add_bootstrap_user_ownership = var.add_bootstrap_user_ownership
  app_registration_name        = "tfe-dynamic-credentials-subscription-b"
}

# dynamic_credentials_azure_run_phases local defined in the subscription_a file

module "dynamic_credentials_azure_management_subscription_b" {
  source   = "git@github.com:permilche/tfe-tf-modules.git//dynamic-credentials/azure/management?ref=main" # cannot use variables there so need to hardcode it
  
  for_each = local.dynamic_credentials_azure_run_phases

  providers = {
    azuread = azuread
  }

  tfc_application_id = module.dynamic_credentials_azure_configuration_subscription_b.tfc_application_id
  tfc_hostname       = var.tfe_hostname
  organization       = module.management_workspace.organization
  project            = var.tfe_management_project_name
  workspace          = module.management_workspace.name
  run_phase          = each.key
  display_name       = "${module.management_workspace.organization}-${var.tfe_management_project_name}-${module.management_workspace.name}-${each.key}-${var.azure_subscriptions["subscription-a"].subscription_id}"
  # added a "custom" display_name to make it easier to identify the dynamic credentials in the Azure Portal, otherwise we end up with the same federated identity display name for different app registrations
}

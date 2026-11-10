module "dynamic_credentials_azure_configuration" {
  source  = "git@github.com:permilche/tfe-tf-modules.git//dynamic-credentials/azure/configuration?ref=main" # cannot use variables there so need to hardcode it

  add_bootstrap_user_ownership = var.add_bootstrap_user_ownership
}

locals {
  dynamic_credentials_azure_run_phases = toset(["plan", "apply"])
}

# The management module creates a single federated credential per workspace/run phase, so loop over the run phases here
module "dynamic_credentials_azure_management" {
  source = "git@github.com:permilche/tfe-tf-modules.git//dynamic-credentials/azure/management?ref=main" # cannot use variables there so need to hardcode it

  for_each = local.dynamic_credentials_azure_run_phases

  tfc_application_id = module.dynamic_credentials_azure_configuration.tfc_application_id
  tfc_hostname       = var.tfe_hostname
  organization       = module.management_workspace.organization
  project            = var.tfe_management_project_name
  workspace          = module.management_workspace.name
  run_phase          = each.key
}

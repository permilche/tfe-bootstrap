# Management Project
module "management_project" {
  # source = "../../project"
  source = "git@github.com:permilche/tfe-tf-modules.git//project?ref=main" # cannot use variables there so need to hardcode it

  organization = var.organization_name
  name         = var.tfe_management_project_name
  description  = "Management project for TFE organization configuration"

  depends_on = [module.organization_settings]
}

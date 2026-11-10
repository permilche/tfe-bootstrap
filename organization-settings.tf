# Organization Settings
module "organization_settings" {
  source = "git@github.com:permilche/tfe-tf-modules.git//organization-settings?ref=main" # cannot use variables there so need to hardcode it

  organization           = var.organization_name
  email                  = var.organization_email
  default_execution_mode = "remote"

  # Optional: Configure session timeout and remember settings
  session_timeout_minutes  = 20160 # 14 days
  session_remember_minutes = 20160 # 14 days

  # SMTP settings (built from the communication-service module + Azure's ACS SMTP relay)
  tfe_admin_smtp_settings = {
    enabled             = true
    host                = "smtp.azurecomm.net"
    port                = 587
    auth                = "login"
    username            = module.azure-communication-service.smtp_username
    password_wo         = module.azure-communication-service.smtp_password
    password_wo_version = 1
    sender              = "${module.azure-communication-service.smtp_username}@${local.smtp_sender_domain}"
    test_email_address  = var.smtp_test_email_address
  }
}

# not exposed as an output either by the avm-res-communication-emailservice module so need to extract it with a data
data "azapi_resource" "email_domain" {
  type        = "Microsoft.Communication/emailServices/domains@2023-04-01"
  resource_id = "${module.avm-res-communication-emailservice.resource_id}/domains/AzureManagedDomain"

  response_export_values = ["properties.mailFromSenderDomain"]

  depends_on = [module.avm-res-communication-emailservice]
}

locals {
  smtp_sender_domain = data.azapi_resource.email_domain.output.properties.mailFromSenderDomain
}

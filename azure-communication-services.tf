module "avm-res-communication-emailservice" {
  source  = "Azure/avm-res-communication-emailservice/azurerm"
  version = "0.2.0"

  # insert the 4 required variables here
  data_location       = "Europe"
  location            = "spain-central"
  name                = "tfe-notifications"
  resource_group_name = var.resource_group_name
  email_communication_service_domains = {
    default = {
      name = "AzureManagedDomain"
      domain_management = "AzureManaged"
    }
  }
  email_communication_service_domain_sender_usernames = {
    (var.smtp_username) = {
        name = var.smtp_username
        email_communication_service_domain_name_key = "default"
    }
  }
}

module "azure-communication-service" {
  source  = "git@github.com:permilche/azure-tf-modules.git//communication-service?ref=main" # cannot use variables there so need to hardcode it

  communication_service_name  = "tfe-notifications"
  resource_group_name         = var.resource_group_name
  data_location               = "Europe"
  email_service_domain_id     = "${module.avm-res-communication-emailservice.resource_id}/domains/AzureManagedDomain"
  app_display_name            = "${var.smtp_username}-smtp"
  role_definition_name        = "Communication and Email Service Owner"
  smtp_username               = var.smtp_username

  depends_on = [ module.avm-res-communication-emailservice ]
}

# IMPORTANT: Note that I re-used the var.smtp_username in both the avm-res-communication-emailservice and the azure-communication-service module, however,
# the azapi_resource.smtp_username from the azure-communication-service module does not need to match the azapi_resource.email_communication_service_domain_sender_username ,
# they serve different purposes. The first one is used for authentication purposes. It links an Entra application (via entraApplicationId + tenantId) to a chosen username,
# which doesn't even need to be an email (it can just be freeform), so the SMTP server knows which identity is logging in via AUTH LOGIN (again, it can be something totally
# different than the sender someone will see when receiveing an email). The second one controls what's allowed to appear as the actual envelope/header sender when an email
# is sent (configured as the "sender" field in the tfe_admin_smtp_settings resource), it is a domain-level allowlist, unrelated to SMTP login credentials! They happen to be
# the same because I am using the smtp_username output of the azure-communication-service module as the name of the sender

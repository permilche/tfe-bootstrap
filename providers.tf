terraform {
  required_version = ">= 1.0"

  required_providers {
    tfe = {
      source  = "hashicorp/tfe"
      version = "~> 0.79.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.60"
    }
    azapi = {
      source  = "Azure/azapi"
      version = "~> 2.4"
    }
  }

  # IMPORTANT: backend blocks are evaluated before variables exist, so var.* and any expression are NOT allowed here,
  # these values have to be hardcoded. Replace the <placeholders> with your own values (or leave them and pass
  # -backend-config=backend.hcl at init time) before running `terraform init`. See Step 1 of the README.md
  backend "azurerm" {
    resource_group_name  = "<resource_group_name>"
    storage_account_name = "<storage_account_name>"
    container_name       = "<container_name>"
    key                  = "terraform.tfstate"
  }
}

provider "tfe" {
  token    = var.tfe_token
  hostname = var.tfe_hostname
}

provider "azurerm" {
  features {}
  subscription_id = var.az_subscription_id
  tenant_id       = var.az_tenant_id
  client_id       = var.az_client_id
  client_secret   = var.az_client_secret
}

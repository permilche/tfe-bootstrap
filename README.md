# TFE Bootstrap Layer

> **Disclaimer:** this is a personal project and not an official HashiCorp product. It is not officially supported or maintained by HashiCorp, and I share it to help out the community. It comes "as is", without any warranty. There may be errors, and the Terraform, provider or module versions used here may get deprecated or stop working. Please review and test everything outside production before using it, and use it at your own risk. The repository is public and issues and pull requests are welcome, but I review and validate each one myself, so there is no guaranteed response time, no promise to merge, and no support SLA (see [CONTRIBUTING](.github/CONTRIBUTING.md)). All names, IDs and values are examples or placeholders, so never commit credentials. Terraform, HCP Terraform and Terraform Enterprise are trademarks of HashiCorp.

> **Looking for a different setup?** This branch (`single-provider-azure-static-credentials`) uses a static Service Principal with a client secret (no OIDC). Check out the other branches for other configurations: `main` for Azure dynamic credentials with one subscription and `multi-provider-azure-dynamic-credentials` for dynamic credentials across several subscriptions.

This directory contains the bootstrap configuration for the Terraform Enterprise (TFE) organization. This is the foundational layer that sets up:

- TFE Organization settings (including the SMTP settings, backed by Azure Communication Services)
- Bootstrap (management) project
- Management workspace (for managing all other TFE resources)
- Private registry workspace (for managing the TFE private module registry)
- SSH key for the private registry workspace's Git access
- Azure Communication Services (email service + SMTP authentication via an Entra ID application)
- Azure provider authentication via Service Principal (client secret)

> The Azure DevOps VCS OAuth client is **not** created by this layer: with the `tfe` provider version used here (`~> 0.79.0`) the `tfe_oauth_client` resource can't create one for Azure DevOps, so [`vcs-oauth.tf`](vcs-oauth.tf) is fully commented out and the OAuth token ID is provided through `vcs_oauth_token_id` instead. Newer provider versions add Azure DevOps support (for example `ado_org_name` for Azure DevOps Services came in 0.82.0, check the provider changelog), so with one of them you should be able to manage the VCS integration as code too.

> **Scope of the cloud authentication.** At the moment this layer focuses on **Azure** authentication only (a Service Principal with a client secret). Authentication for other cloud providers (AWS, GCP, ...) is planned and will be added in the future.

## Authentication Method

**Branch `single-provider-azure-static-credentials`: single provider, Azure static credentials (Service Principal with a client secret).** This branch does **not** use dynamic credentials.

- **Bootstrap layer (this repository, run locally):** the `azurerm` provider authenticates with a Service Principal that **you create beforehand** (`az_subscription_id`, `az_tenant_id`, `az_client_id`, `az_client_secret`). The `azuread` and `azapi` providers use your Azure CLI session.
- **Management workspace (TFE):** the same Service Principal credentials are passed to the workspace as Terraform variables (`az_client_secret` marked sensitive), so the secret **is stored in TFE** and has to be rotated manually. The management repository must declare those variables and wire them into its own `azurerm` provider.
- **Scope:** one Service Principal, one subscription, one tenant. For OIDC dynamic credentials without stored secrets see the `main` branch (one subscription) or `multi-provider-azure-dynamic-credentials` (several subscriptions).

## Architecture

The bootstrap layer uses **Terraform Community Edition** with an **Azure Blob Storage backend** to manage the initial TFE configuration. Once deployed, the management workspace in TFE will manage all subsequent TFE resources through a VCS-driven workflow.

```
┌─────────────────────────────────────────────────────────────┐
│                    Bootstrap Layer (Local)                  │
│  - Terraform CE with Azure Blob Storage backend             │
│  - Creates: Organization, Project, Workspaces, SSH key, ACS │
│  - Authenticates to Azure via Service Principal             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│           TFE Management Workspace (VCS-driven)             │
│  - Connected to Azure DevOps repository                     │
│  - Manages all other TFE modules and resources              │
│  - Receives az_client_id / az_client_secret variables       │
└─────────────────────────────────────────────────────────────┘
```

## Dependencies and Related Repositories

This layer does not work on its own. It depends on, and hands off to, the following repositories:

| Repository | Relationship |
|---|---|
| [`tfe-tf-modules`](https://github.com/permilche/tfe-tf-modules) | **Hard dependency.** Source of the TFE modules used by this layer (`organization-settings`, `project`, `ssh-key`, `workspace`). They are downloaded over SSH on `terraform init` (see [Module Sources](#module-sources)). It is also the repository whose modules end up in the organization's private registry and that the management layer consumes afterwards |
| [`azure-tf-modules`](https://github.com/permilche/azure-tf-modules) | **Hard dependency.** Source of the `communication-service` module (Azure Communication Services with SMTP authentication) |
| [`tfe-private-registry`](https://github.com/permilche/tfe-private-registry) | **Created and wired by this layer.** This layer creates the `tfe-private-registry` workspace (connected to the repository set in `vcs_repository_private_registry`, with the SSH key created here). That repository publishes the `tfe-tf-modules` modules to the organization's private registry |
| [`tfe-management`](https://github.com/permilche/tfe-management) | **Created and wired by this layer.** This layer creates the `tfe-management` workspace (connected to the repository set in `vcs_repository_management`) and injects the variables it needs. That repository takes over the management of every other TFE resource and consumes the modules from the private registry |

This branch is an alternative to the `main` branch (Azure dynamic credentials with OIDC): here Azure authentication uses a static Service Principal with a client secret. See the `main` branch `README.md` for the dynamic credentials baseline and the `multi-provider-azure-dynamic-credentials` branch for several subscriptions.
## Module Sources

The modules used by this layer are **not** consumed from the HCP Terraform / TFE private registry, because this layer is the one that creates the registry workspace (chicken-and-egg). They are pulled over SSH from Git instead:

| Module | Source |
|---|---|
| `organization-settings`, `project`, `ssh-key`, `workspace` (and the commented-out `vcs-oauth`) | `git@github.com:permilche/tfe-tf-modules.git//<module>?ref=main` |
| `azure-communication-service` | `git@github.com:permilche/azure-tf-modules.git//communication-service?ref=main` |
| `avm-res-communication-emailservice` | `Azure/avm-res-communication-emailservice/azurerm` (public Terraform registry, pinned to `0.2.0`) |

> **Note:** the deprecated `tf-modules` repository is no longer used. The TFE modules live in `tfe-tf-modules` and the Azure ones in `azure-tf-modules`.
>
> **Note:** a module `source` cannot contain variables or expressions, so every `source` in this layer is hardcoded (each one carries a `# cannot use variables there so need to hardcode it` comment). If you fork this layer, update them by hand. You need an SSH key with read access to those GitHub repositories on the machine running `terraform init`.
>
> **Note:** the HCP Terraform FQDN (`app.terraform.io`) is **not** used in any `source` here. Once the private registry is populated, the *management* repository should consume the modules from it. See [Module Usage Reference](#module-usage-reference).
>
> **Warning: sources are not pinned to a tag (do not do this in production).** The Git sources use `?ref=main`, which resolves to the **latest commit of the branch** every time modules are downloaded. A change pushed to `tfe-tf-modules` or `azure-tf-modules` can therefore alter what the next `terraform init -upgrade` / run applies, so two applies of the same code are **not guaranteed to behave the same**. It is better to pin a tag (or a commit SHA), for example `?ref=v1.0.0`, and bump it deliberately. This configuration keeps the branch reference for simplicity while it is being developed. Neither module repository publishes tags yet. The same applies to the private registry sources the management repository consumes: set a `version` argument on each module. Only the public `avm-res-communication-emailservice` module is already pinned (`version = "0.2.0"`).

## Prerequisites

### 1. Azure Resources
- Azure Storage Account for Terraform state
- Resource Group
- Container for state storage (will be created if it doesn't exist)
- A Service Principal with a client secret (see below)

### 2. TFE / HCP Terraform Organization
- Organization name
- TFE API token with organization admin permissions
- TFE hostname (`app.terraform.io` for HCP Terraform, the FQDN of your instance if you run TFE self-hosted)

### 3. Azure DevOps
- Organization
- Project
- Repository for the management layer (`vcs_repository_management`)
- Repository for the private registry layer (`vcs_repository_private_registry`)
- OAuth token ID for the VCS integration (created manually in TFE, see Step 6)
- A private SSH key with read access to those repositories (`ssh_private_key`)

### 4. Local Environment
- Terraform >= 1.0 (the `communication-service` module declares `>= 1.9`, so use 1.9 or later)
- Azure CLI (authenticated, used for the backend and by the `azuread`/`azapi` providers, see [Azure Service Principal Authentication](#azure-service-principal-authentication))
- Git, and an SSH key with read access to the `tfe-tf-modules` and `azure-tf-modules` GitHub repositories

### 5. Permissions Required to Run This Layer

The identity running `terraform apply` here needs the following. Everything is created by you, locally, so a missing permission fails the apply, not the management workspace.

| Where | Role | Why |
|-------|------|-----|
| Azure RBAC (subscription or resource group) | `Contributor` | The `azurerm` Service Principal creates the Azure resources (for example the Communication Services resources). |
| Azure RBAC (same scope) | `Owner`, `User Access Administrator` or `Role Based Access Control Administrator` | `Contributor` cannot write role assignments, and the Communication Services module assigns a role. |
| Microsoft Entra ID | `Application Administrator`, `Cloud Application Administrator` or `Application Developer` | The `azuread` provider (your Azure CLI session) creates the App Registration and Service Principal used for SMTP. |
| State storage account | `Storage Blob Data Contributor` | Read and write the Terraform state in the Blob container. |
| TFE / HCP Terraform | Organization owner token | Creates the organization settings, project, workspaces and VCS connection. |

This branch does not create dynamic credentials, so no Microsoft Graph permission grant is needed. The Service Principal you pre-create for the management workspace is yours to manage, and its secret is stored in TFE.

## Before You Start: Values to Replace

Some values cannot be variables in Terraform and others are specific to the author's environment. Review this list **before** the first `terraform init`:

1. **Backend (`providers.tf`).** The `backend "azurerm"` block ships with the placeholders `<resource_group_name>`, `<storage_account_name>` and `<container_name>`. Backend blocks cannot use variables or expressions, so they must be hardcoded: replace them in the file, or pass real values at init time with `-backend-config=backend.hcl` (see [Step 1](#step-1-configure-azure-backend)).
2. **TFE hostname (`tfe_hostname`).** Set it in `terraform.tfvars`: `app.terraform.io` for **HCP Terraform**, or the FQDN of your instance for **self-hosted TFE** (e.g. `tfe.example.com`). The same applies wherever the README shows `app.terraform.io` (the `curl` check, the private registry module sources of the management repository).
3. **HCP Terraform vs. self-hosted TFE (SMTP).** The `tfe_admin_smtp_settings` resource is an instance-level setting of **self-hosted TFE** and has no effect on HCP Terraform. If you use HCP Terraform, remove the Azure Communication Services part: delete `azure-communication-services.tf`, the `tfe_admin_smtp_settings` block, the `data "azapi_resource" "email_domain"` and the `locals` in `organization-settings.tf`, the `# ACS info` outputs in `outputs.tf` and the `resource_group_name`, `smtp_username` and `smtp_test_email_address` variables.
4. **Module sources.** Every module `source` points at `git@github.com:permilche/...`. If you use your own copy of the modules, update each `source` (and its `ref`) by hand: sources cannot use variables. You also need an SSH key with read access to those repositories.
5. **VCS provider.** `workspace.tf` assumes Azure DevOps (`vcs_provider = "azure_devops"`). For another VCS provider adapt the `vcs_repo` blocks and create the OAuth client accordingly.
6. **Azure Communication Services values.** `azure-communication-services.tf` hardcodes the region (`location = "spain-central"`), the data location (`"Europe"`) and the resource names (`tfe-notifications`). Change them to suit your environment. The resource group comes from `var.resource_group_name` and must already exist.
7. **Values without a default.** `resource_group_name` and the rest of the required variables have **no default on purpose**: you must provide them in `terraform.tfvars` (see `terraform.tfvars.example`).

## Setup Instructions

### Step 1: Configure Azure Backend

Ensure you're authenticated with Azure CLI:

```bash
az login
az account set --subscription <your-subscription-id>
```

Create the storage container if it doesn't exist:

```bash
az storage container create \
  --name tfe-bootstrap-layer \
  --account-name <your-storage-account> \
  --resource-group <your-resource-group>
```

> **Important: backend values cannot use variables.** Terraform's `backend` block is evaluated before the variable system is initialized, so expressions and `var.*` references are not allowed inside it. That is why `providers.tf` ships with the placeholders `<resource_group_name>`, `<storage_account_name>` and `<container_name>`, with a comment explaining it: **you must replace them** (they must be hardcoded, they cannot come from `terraform.tfvars`). There are two ways to do it:
>
> **Option A: `-backend-config` file (recommended, nothing environment specific is committed):** keep the placeholders and pass the real values at init time. `backend.hcl` is already in `.gitignore`:
> ```bash
> # backend.hcl  (gitignored)
> resource_group_name  = "your-resource-group"
> storage_account_name = "your-storage-account"
> container_name       = "tfe-bootstrap-layer"
> key                  = "terraform.tfstate"
> ```
> ```bash
> terraform init -backend-config=backend.hcl
> ```
>
> **Option B: hardcode them in `providers.tf`:** replace the three placeholders in the `backend "azurerm"` block and run a plain `terraform init`.

### Step 2: Create an Azure Service Principal

Create a Service Principal and generate a client secret:

```bash
az ad sp create-for-rbac \
  --name "tfe-bootstrap-sp" \
  --role Contributor \
  --scopes /subscriptions/<your-subscription-id>
```

This outputs `appId` (`az_client_id`), `password` (`az_client_secret`), and `tenant` (`az_tenant_id`). Note all three values.

### Step 3: Set Environment Variables

Set sensitive variables as environment variables:

```bash
# TFE Token
export TF_VAR_tfe_token="your-tfe-organization-token"

# Azure Service Principal secret (keep out of tfvars)
export TF_VAR_az_client_secret="your-service-principal-client-secret"

# Azure Backend Authentication (if not using Azure CLI)
export ARM_ACCESS_KEY="your-storage-account-access-key"
# OR use Azure CLI authentication (recommended)
```

### Step 4: Create terraform.tfvars

Copy the example file and customize:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
organization_name  = "your-org-name"
organization_email = "your-admin-email@example.com"

# HCP Terraform FQDN (use your own FQDN if self-hosted). The token is set via TF_VAR_tfe_token
tfe_hostname = "app.terraform.io"

vcs_oauth_token_id = "mock-up-value" # replace with the real OAuth token ID after Step 6
vcs_https_url     = "https://dev.azure.com/your-org"
vcs_api_url       = "https://dev.azure.com/your-org"
vcs_organization  = "your-ado-org"
vcs_project       = "your-ado-project"
vcs_repository_management       = "tfe-management"
vcs_repository_private_registry = "tfe-private-registry"

# Azure Communication Services (SMTP)
resource_group_name     = "your-resource-group"
smtp_username           = "notifications"
smtp_test_email_address = "admin@example.com"

# SSH key used by the private registry workspace to clone the module repositories
ssh_private_key = <<EOT
-----BEGIN RSA PRIVATE KEY-----
...
-----END RSA PRIVATE KEY-----
EOT

# Azure Service Principal configuration
az_subscription_id = "your-subscription-id"
az_tenant_id       = "your-tenant-id"
az_client_id       = "your-service-principal-app-id"
# az_client_secret is set via TF_VAR_az_client_secret env variable

vcs_branch        = "main"
terraform_version = "1.5.0"
auto_apply        = false
```

### Step 5: Initialize Terraform

```bash
# Option A: real backend values in backend.hcl (see the Step 1 note above)
terraform init -backend-config=backend.hcl

# Option B: you already replaced the placeholders in providers.tf
terraform init
```

This will:
- Download the TFE, AzureRM, AzureAD and AzAPI providers
- Download the modules from the `tfe-tf-modules` and `azure-tf-modules` Git repositories (over SSH)
- Configure the Azure backend
- Initialize the working directory

### Step 6: Plan and Apply

Review the planned changes:

```bash
terraform plan
```

Apply the configuration:

```bash
terraform apply
```

This will create:
- TFE organization settings (with the SMTP settings wired to Azure Communication Services)
- Management project in TFE
- SSH key in TFE for the private registry workspace
- Management workspace in TFE (connected to Azure DevOps, with the `az_*` Terraform variables pre-configured)
- Private registry workspace in TFE (connected to Azure DevOps, with the SSH key)
- Azure Email Communication Service, Communication Service and the Entra ID application used for SMTP authentication

> **VCS OAuth (Azure DevOps):** this layer does not create the VCS provider. On the first deployment use the default mock-up value of `vcs_oauth_token_id`, then manually create the VCS provider in TFE, get the OAuth token ID and re-apply with the real value. You also need to enable OAuth Applications in Azure DevOps and create an App Registration in the same tenant.

### Step 7: Verify Management Workspace

After successful apply, you'll see outputs including:

```
management_workspace_html_url       = "https://app.terraform.io/app/<organization_name>/workspaces/tfe-management"
private_registry_workspace_html_url = "https://app.terraform.io/app/<organization_name>/workspaces/tfe-private-registry"
```

Visit these URLs to verify the workspaces were created correctly.

## Azure Service Principal Authentication

This bootstrap layer authenticates to Azure using a **Service Principal with a client secret**, as described in the [AzureRM provider documentation](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/guides/service_principal_client_secret).

### How It Works

The `azurerm` provider is configured with explicit Service Principal credentials:

```hcl
provider "azurerm" {
  features {}
  subscription_id = var.az_subscription_id
  tenant_id       = var.az_tenant_id
  client_id       = var.az_client_id
  client_secret   = var.az_client_secret
}
```

Only the `azurerm` provider is configured with the Service Principal. The `azuread` and `azapi` providers (used inside the `azure-communication-service` module) have no explicit configuration in [`providers.tf`](providers.tf), so they use their default authentication (Azure CLI session or `ARM_*` environment variables). Make sure you are logged in with `az login` (or export the `ARM_*` variables) with an identity that can create Entra ID applications.

The same credentials are also passed to the **management workspace** as `terraform`-category workspace variables (**not** `ARM_*` environment variables), so the configuration in the management repository must declare them and wire them into its own `azurerm` provider:

| Variable | Category | Sensitive | Description |
|---|---|---|---|
| `az_subscription_id` | terraform | no | Azure subscription ID |
| `az_tenant_id` | terraform | no | Azure tenant ID |
| `az_client_id` | terraform | no | Service Principal `appId` |
| `az_client_secret` | terraform | yes | Service Principal client secret |

### Keeping the Client Secret Secure

The `az_client_secret` variable is declared `sensitive = true`. It is recommended to supply it via environment variable rather than committing it to `terraform.tfvars`:

```bash
export TF_VAR_az_client_secret="your-secret-here"
```

## Azure Communication Services Configuration

> **Self-hosted TFE only.** The SMTP settings are an instance-level setting of self-hosted TFE and have no effect on HCP Terraform. If you use HCP Terraform, remove this part as described in [Before You Start](#before-you-start-values-to-replace).

This bootstrap layer optionally configures Azure Communication Services for TFE email notifications via SMTP. This setup creates the necessary Azure resources to enable TFE to send notification emails.

### Architecture

The configuration uses two modules to set up email capabilities:

1. **Email Service Module** (`avm-res-communication-emailservice`): Creates the Azure Communication Services Email Service with an Azure-managed domain
2. **Communication Service Module** (`azure-communication-service`): Creates the Communication Service, links it to the email domain, and sets up SMTP authentication via an Entra ID application

### Configuration

The setup is defined in [`azure-communication-services.tf`](azure-communication-services.tf):

```hcl
module "avm-res-communication-emailservice" {
  source  = "Azure/avm-res-communication-emailservice/azurerm"
  version = "0.2.0"

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
  source = "git@github.com:permilche/azure-tf-modules.git//communication-service?ref=main" # cannot use variables there so need to hardcode it

  communication_service_name  = "tfe-notifications"
  resource_group_name         = var.resource_group_name
  data_location               = "Europe"
  email_service_domain_id     = "${module.avm-res-communication-emailservice.resource_id}/domains/AzureManagedDomain"
  app_display_name            = "${var.smtp_username}-smtp"
  role_definition_name        = "Communication and Email Service Owner"
  smtp_username               = var.smtp_username

  depends_on = [module.avm-res-communication-emailservice]
}
```

### IMPORTANT: Understanding smtp_username Usage

The `var.smtp_username` variable is used in **both** modules but serves **completely different purposes**:

#### 1. SMTP Authentication Username (azure-communication-service module)

The `azapi_resource.smtp_username` resource created by the `azure-communication-service` module is used for **SMTP authentication purposes**. It:

- Links an Entra ID application (via `entraApplicationId` + `tenantId`) to a chosen username
- **Does NOT need to be an email address**: it can be any freeform string
- Tells the SMTP server which identity is logging in via `AUTH LOGIN`
- Is used as the SMTP login credential when TFE connects to Azure Communication Services
- Can be completely different from what recipients see as the sender

**Example**: You could use `"tfe-smtp-auth"` as the authentication username, even though emails appear to come from `"notifications@yourdomain.com"`.

#### 2. Sender Allowlist (avm-res-communication-emailservice module)

The `azapi_resource.email_communication_service_domain_sender_username` resource created by the `avm-res-communication-emailservice` module controls **what sender addresses are allowed**. It:

- Defines a domain-level allowlist of permitted sender addresses
- Controls what can appear as the actual envelope/header sender when an email is sent
- Is configured as the `sender` field in the `tfe_admin_smtp_settings` resource
- Is **completely unrelated to SMTP login credentials**
- Determines what recipients see in the "From" field of emails

**Example**: This allowlist entry `"notifications@AzureManagedDomain"` allows TFE to send emails with that address in the From field.

#### Why They're the Same in This Configuration

In this bootstrap configuration, both use the same `var.smtp_username` value because:

1. The `smtp_username` output from the `azure-communication-service` module is used as the sender address
2. This creates a simple, consistent configuration where the authentication username matches the sender address
3. It's a convenience choice, not a technical requirement

**You could configure them differently**:
- Authentication username: `"tfe-smtp-login"`
- Sender address: `"notifications@yourdomain.com"`

Both would work fine as long as:
- The authentication username is linked to a valid Entra ID application
- The sender address is in the domain's allowlist

### Variables

Configure these variables in `terraform.tfvars`:

```hcl
# Required for Azure Communication Services
smtp_username = "notifications"  # Used for both SMTP auth and sender address

# Optional - for testing SMTP configuration
smtp_test_email_address = "admin@example.com"
```

### Outputs

After applying, the configuration outputs:

- `email_communication_service`
- `email_communication_service_id`
- `email_communication_service_in_azurerm_schema`

The SMTP credentials (`smtp_username` and the sensitive `smtp_password`) are outputs of the `azure-communication-service` **module**. They are **not** re-exported by this layer, so they never show up in `terraform output`.

### Integration with TFE

The SMTP settings are wired directly from the module outputs in [`organization-settings.tf`](organization-settings.tf), through the `tfe_admin_smtp_settings` input of the `organization-settings` module:

```hcl
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
```

`local.smtp_sender_domain` is read from the `AzureManagedDomain` with an `azapi_resource` data source, because the AVM email module does not expose it as an output. The password is passed through the write-only `password_wo` argument, so the `tfe_admin_smtp_settings` resource does not persist it in its state. The underlying Entra ID application password is still stored in the bootstrap state, so keep access to the Azure Blob Storage backend restricted.

### Security Considerations

1. **Credentials**: SMTP password (application secret) is sensitive and should be stored securely
2. **Sender Validation**: Only allowlisted sender addresses can be used
3. **Authentication**: SMTP authentication is required via Entra ID application
4. **TLS**: Always use STARTTLS (port 587) for encrypted communication
5. **Rotation**: Regularly rotate the application secret used for SMTP authentication

### Troubleshooting

**Issue: SMTP authentication fails**
- Verify the Entra ID application exists and has correct permissions
- Check that the application secret hasn't expired
- Ensure the username matches the configured SMTP username resource

**Issue: Sender address rejected**
- Verify the sender address is in the domain's allowlist
- Check that the domain is properly configured and verified
- Ensure the sender format matches the allowlist entry exactly

**Issue: Emails not being delivered**
- Check Azure Communication Services quotas and limits
- Verify the domain's DNS records (if using custom domain)
- Review Azure Communication Services logs for delivery failures

## Next Steps: Setting Up the Management Layer

> The examples below are brief. For the full working code, see [tfe-private-registry](https://github.com/permilche/tfe-private-registry) and [tfe-management](https://github.com/permilche/tfe-management).

This layer creates two VCS-driven workspaces that you then populate: first `tfe-private-registry`, then `tfe-management`. The order matters because the management configuration consumes modules from the private registry, not from Git, so they must be published before the management workspace can plan.

**The first run of each workspace has to be started manually.** A workspace with no runs does not accept runs from a VCS webhook, so queue one run by hand in the UI, as described in [Automatically starting runs](https://developer.hashicorp.com/terraform/enterprise/workspaces/run/ui#automatically-starting-runs). After that, pushes to the repository trigger runs automatically.

### 1. Initialize the Private Registry Workspace

1. Clone the repository connected to the `tfe-private-registry` workspace (`vcs_repository_private_registry`) and add the configuration that publishes the `tfe-tf-modules` modules to the private registry. See [tfe-private-registry](https://github.com/permilche/tfe-private-registry) for a complete example.
2. The workspace already has the variables it needs, injected by this layer: `organization`, `tfe_token`, `tfe_hostname` and `vcs_oauth_token_id`.
3. Push the code, then queue the first run manually in the UI and apply it.
4. Check that the modules show up in the private registry of your organization before moving on.

### 2. Switch to the Management Repository

Navigate to your local clone of the management repository (the repository connected to the `tfe-management` workspace).

### 3. Create the TFE Configuration

In the management repository, create Terraform configuration that uses the TFE modules to manage all other TFE resources. Example structure:

```
management-repo/
├── main.tf              # Main configuration
├── providers.tf         # TFE and Azure providers
├── variables.tf         # Input variables
├── outputs.tf           # Outputs
├── teams.tf             # Team configurations
├── projects.tf          # Project configurations
├── workspaces.tf        # Workspace configurations
└── terraform.tfvars     # Variable values
```

Example `providers.tf` for the management repository:

```hcl
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
  }
  
  # No backend block - TFE manages state automatically
}

provider "tfe" {
  token    = var.tfe_token
  hostname = var.tfe_hostname # injected by the bootstrap layer (app.terraform.io for HCP Terraform)
}

provider "azurerm" {
  features {}
  subscription_id = var.az_subscription_id
  tenant_id       = var.az_tenant_id
  client_id       = var.az_client_id
  client_secret   = var.az_client_secret
  # az_* are Terraform variables injected in the workspace by the bootstrap layer,
  # declare them in the management repository's variables.tf
}
```

### 4. Configure Workspace Variables

The management workspace has these variables pre-configured by the bootstrap layer:
- `organization`: TFE organization name
- `tfe_token` (sensitive) / `tfe_hostname`, TFE API credentials
- `vcs_oauth_token_id` / `vcs_org` / `vcs_project`, VCS connection details
- `az_subscription_id` / `az_tenant_id` / `az_client_id`, Azure Service Principal identifiers
- `az_client_secret` (sensitive), Service Principal client secret

### 5. Push and Trigger

```bash
git add .
git commit -m "Initial TFE configuration"
git push origin main
```

Once the private registry modules are published, queue the first `tfe-management` run manually in the UI (see the note at the start of this section). From then on, pushes trigger runs automatically.

## Module Usage Reference

The management repository should use the TFE modules to manage all resources. Once the `tfe-private-registry` workspace has published the modules, consume them from the private registry of your organization (`<HOSTNAME>/<ORG>/<NAME>/tfe`). For HCP Terraform the hostname is `app.terraform.io`:

```hcl
module "project" {
  source = "app.terraform.io/<organization_name>/project/tfe" # cannot use variables there so need to hardcode it
  # version = "x.y.z" # pin it in production
}
```

> A module `source` cannot use variables, so the HCP Terraform FQDN (`app.terraform.io`) and the organization name must be hardcoded. If you run TFE self-hosted, use your own FQDN there. The bootstrap layer itself cannot do this (it creates the registry workspace), which is why it uses the Git sources described in [Module Sources](#module-sources).

Key modules include:

- **project**: Create projects to organize workspaces
- **team**: Create teams for access control
- **workspace**: Create workspaces for infrastructure management
- **variable-set**: Share variables across workspaces
- **policy-set**: Enforce governance policies
- **run-task**: Integrate security/cost tools

## State Management

### Bootstrap Layer (This Directory)
- **Backend**: Azure Blob Storage
- **State File**: `terraform.tfstate` in configured container
- **Management**: Manual Terraform commands (`terraform plan` / `terraform apply`)

### Management Workspace (TFE)
- **Backend**: TFE managed state
- **State File**: Managed automatically by TFE
- **Management**: VCS-driven workflow (automatic runs on git push)

## Troubleshooting

### Issue: `terraform init` cannot download the modules

- Confirm your SSH key has read access to `permilche/tfe-tf-modules` and `permilche/azure-tf-modules` on GitHub (`ssh -T git@github.com`)
- Check that the `ref=` in the `source` exists in those repositories

### Issue: Backend initialization fails

First make sure you replaced the `<resource_group_name>`, `<storage_account_name>` and `<container_name>` placeholders of the `backend` block in `providers.tf` (or that you pass `-backend-config=backend.hcl`).


```bash
# Verify Azure authentication
az account show

# Check storage account access
az storage container show \
  --name tfe-bootstrap-layer \
  --account-name <your-storage-account> \
  --resource-group <your-resource-group>
```

### Issue: TFE authentication fails

```bash
# Verify TFE token (replace app.terraform.io with your TFE FQDN if self-hosted)
curl -H "Authorization: Bearer $TF_VAR_tfe_token" \
  https://app.terraform.io/api/v2/account/details
```

### Issue: VCS OAuth connection fails

- Verify the OAuth token has correct permissions in Azure DevOps
- Check that the repository exists and is accessible
- Ensure the OAuth token hasn't expired

### Issue: Workspace not triggering runs

- Verify the VCS connection in TFE UI
- Check webhook configuration in Azure DevOps
- Ensure the branch name matches the configuration

### Issue: Azure authentication fails (Service Principal)

- Verify the `az_client_id` / `az_client_secret` / `az_tenant_id` values are correct
- Check that the Service Principal has not expired (client secret rotation)
- Ensure the Service Principal has the required role assignments on the subscription
- Confirm the Service Principal is not disabled in Entra ID

### Issue: Data source error

```bash
│ Error: Resource not found
│
│   with data.azapi_resource.email_domain,
│   on organization-settings.tf line 29, in data "azapi_resource" "email_domain":
│   29: data "azapi_resource" "email_domain" {
│
│ resource "Resource: (ResourceId
│ \"/subscriptions/.../emailServices/tfe-notifications/domains/AzureManagedDomain\"
│ / Api Version \"2023-04-01\")" not found
```
You might encounter this on the first apply since the resources do not exist yet. Re-apply to resolve it.

### Issue: Error creating AdminSMTP Settings

```bash
│ Error: Error creating AdminSMTP Settings
│
│   with module.organization_settings.tfe_admin_smtp_settings.this[0],
│   ...
│ Could not set Admin SMTP Settings, unexpected error: failed to update Admin SMTP Settings: unauthorized
```
Seen occasionally, re-apply to resolve it.

## Maintenance

### Updating the Bootstrap Configuration

To make changes to the bootstrap layer:

1. Update the Terraform files in this directory
2. Run `terraform plan` to review changes
3. Run `terraform apply` to apply changes
4. Changes will be reflected in the TFE organization

### Destroying the Bootstrap Layer

**WARNING**: This will destroy the TFE organization configuration!

```bash
terraform destroy
```

This will remove:
- Management workspace
- Bootstrap project
- VCS OAuth connection
- Organization settings

## Security Best Practices

1. **Never commit `az_client_secret`** to version control, use `TF_VAR_az_client_secret` instead
2. **Use environment variables** for tokens and secrets. `terraform.tfvars` (which holds your real values, including `ssh_private_key`) is ignored by `.gitignore` (`*.tfvars`), as are `.terraform*` and `*.tfstate*`. Only `terraform.tfvars.example`, with placeholders, is committed
3. **Enable MFA** on TFE accounts
4. **Rotate the Service Principal client secret regularly**
5. **Use least-privilege access**: grant only the roles required by the Service Principal
6. **Enable audit logging** in TFE
7. **Review workspace permissions** regularly
8. **Separate Service Principals per environment** for production workloads

## Support

This project is offered as is and **no support is provided** (see the disclaimer at the top of this README and [SUPPORT](.github/SUPPORT.md)). For issues or questions, these resources are the best place to start:

- The README of each module used here, in [`tfe-tf-modules`](https://github.com/permilche/tfe-tf-modules) and [`azure-tf-modules`](https://github.com/permilche/azure-tf-modules)
- [TFE documentation](https://developer.hashicorp.com/terraform/enterprise)
- [TFE provider documentation](https://registry.terraform.io/providers/hashicorp/tfe/latest/docs)

## License

Licensed under the [Mozilla Public License 2.0](LICENSE). See also [CONTRIBUTING](.github/CONTRIBUTING.md), [SUPPORT](.github/SUPPORT.md) and [SECURITY](.github/SECURITY.md).

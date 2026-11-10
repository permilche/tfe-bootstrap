# TFE Bootstrap Layer

> **Disclaimer:** this is a personal project and not an official HashiCorp product. It is not officially supported or maintained by HashiCorp, and I share it to help out the community. It comes "as is", without any warranty. There may be errors, and the Terraform, provider or module versions used here may get deprecated or stop working. Please review and test everything outside production before using it, and use it at your own risk. The repository is public and issues and pull requests are welcome, but I review and validate each one myself, so there is no guaranteed response time, no promise to merge, and no support SLA (see [CONTRIBUTING](.github/CONTRIBUTING.md)). All names, IDs and values are examples or placeholders, so never commit credentials. Terraform, HCP Terraform and Terraform Enterprise are trademarks of HashiCorp.

> **Looking for a different setup?** This branch (`multi-provider-azure-dynamic-credentials`) covers several Azure subscriptions of the same tenant, with one aliased `azurerm` provider and one App Registration per subscription. Check out the other branches for other configurations: `main` for the single-subscription dynamic credentials baseline and `single-provider-azure-static-credentials` for a static Service Principal with a client secret.

This directory contains the bootstrap configuration for the Terraform Enterprise (TFE) organization. This is the foundational layer that sets up:

- TFE Organization settings (including SMTP via Azure Communication Services)
- Azure DevOps VCS integration
- Bootstrap project and management workspace (for managing all other TFE resources)
- Private registry workspace (for managing the TFE private module/provider registry)
- SSH key for private registry Git access
- Azure Dynamic Credentials base infrastructure

> **Scope of the cloud authentication.** At the moment this layer focuses on **Azure** authentication only (dynamic credentials through OIDC federation with Entra ID, one App Registration per subscription). Authentication for other cloud providers (AWS, GCP, ...) is planned and will be added in the future.

## Authentication Method

**Branch `multi-provider-azure-dynamic-credentials`: multiple providers (one per subscription), Azure dynamic credentials (OIDC).**

- **Bootstrap layer (this repository, run locally):** the `azurerm` and `azuread` providers use your Azure CLI session (`az login`). No Service Principal secret is configured.
- **Management workspace (TFE):** for **each** subscription in `azure_subscriptions` there is an aliased `azurerm` provider, a `dynamic-credentials/azure/configuration` module call (its own App Registration and Service Principal) and federated credentials for the management workspace (plan and apply phases). TFE authenticates to Azure through OIDC using the TAG-based variables `TFC_AZURE_PROVIDER_AUTH_<TAG>`, `TFC_AZURE_RUN_CLIENT_ID_<TAG>`, `ARM_SUBSCRIPTION_ID_<TAG>` and `ARM_TENANT_ID_<TAG>`. **No Azure secret is stored in TFE.**
- **Scope:** several subscriptions of the same tenant. For the single App Registration baseline see the `main` branch. For a static Service Principal with a client secret see the `single-provider-azure-static-credentials` branch.

## Architecture

The bootstrap layer uses **Terraform Community Edition** with an **Azure Blob Storage backend** to manage the initial TFE configuration. Once deployed, the management workspace in TFE will manage all subsequent TFE resources through a VCS-driven workflow.

```
┌─────────────────────────────────────────────────────────────┐
│                    Bootstrap Layer (Local)                  │
│  - Terraform CE with Azure Blob Storage backend             │
│  - Creates: Organization, Project, Workspaces               │
│  - Creates: SSH key for private registry Git access         │
│  - Creates: Azure Dynamic Credentials base infrastructure   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│           TFE Management Workspace (VCS-driven)             │
│  - Connected to Azure DevOps repository                     │
│  - Manages all other TFE modules and resources              │
│  - Creates workspace-specific federated credentials         │
└─────────────────────────────────────────────────────────────┘
```

## Dependencies and Related Repositories

This layer does not work on its own. It depends on, and hands off to, the following repositories:

| Repository | Relationship |
|---|---|
| [`tfe-tf-modules`](https://github.com/permilche/tfe-tf-modules) | **Hard dependency.** Source of the TFE modules used by this layer (`organization-settings`, `project`, `ssh-key`, `workspace`, `dynamic-credentials/azure/configuration`, `dynamic-credentials/azure/management`). They are downloaded over SSH on `terraform init` (see [Module Sources](#module-sources)). It is also the repository whose modules end up in the organization's private registry and that the management layer consumes afterwards |
| [`azure-tf-modules`](https://github.com/permilche/azure-tf-modules) | **Hard dependency.** Source of the `communication-service` module (Azure Communication Services with SMTP authentication) |
| [`tfe-private-registry`](https://github.com/permilche/tfe-private-registry) | **Created and wired by this layer.** This layer creates the `tfe-private-registry` workspace (connected to the repository set in `vcs_repository_private_registry`, with the SSH key created here). That repository publishes the `tfe-tf-modules` modules to the organization's private registry |
| [`tfe-management`](https://github.com/permilche/tfe-management) | **Created and wired by this layer.** This layer creates the `tfe-management` workspace (connected to the repository set in `vcs_repository_management`) and injects the variables it needs. That repository takes over the management of every other TFE resource and consumes the modules from the private registry |

This branch builds on the `main` branch (single App Registration, single subscription) and extends it to several subscriptions. See the `main` branch `README.md` for the baseline scenario and the `single-provider-azure-static-credentials` branch for static Service Principal authentication.
## Module Sources

The modules used by this layer are **not** consumed from the HCP Terraform / TFE private registry, because this layer is the one that creates the registry workspace (chicken-and-egg). They are pulled over SSH from Git instead:

| Module | Source |
|---|---|
| `organization-settings`, `project`, `ssh-key`, `workspace` (and the commented-out `vcs-oauth`) | `git@github.com:permilche/tfe-tf-modules.git//<module>?ref=main` |
| `dynamic-credentials/azure/configuration` and `dynamic-credentials/azure/management` | `git@github.com:permilche/tfe-tf-modules.git//dynamic-credentials/azure/<configuration\|management>?ref=main` |
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

### 2. TFE Organization
- Organization name
- TFE API token with organization admin permissions
- TFE hostname (`app.terraform.io` for HCP Terraform, the FQDN of your instance if you run TFE self-hosted)

### 3. Azure DevOps
- Organization
- Project
- Repository for management layer
- Repository for private registry layer
- OAuth token for VCS integration (must be created manually in TFE, see Step 5 note)

### 4. Local Environment
- Terraform >= 1.9 (the `communication-service` module requires it, the configuration itself declares `>= 1.0`)
- Azure CLI (authenticated)
- Git, and an SSH key with read access to the `tfe-tf-modules` and `azure-tf-modules` GitHub repositories

### 5. Permissions Required to Run This Layer

This layer pre-creates the Azure resources that `tfe-management` needs for dynamic credentials: an App Registration, a Service Principal, role assignments and the federated credentials. The identity running `terraform apply` here (your Azure CLI session) needs the permissions below, otherwise the apply fails before the management workspace ever runs. With several subscriptions, the Azure RBAC rows apply to **each** subscription the Dynamic Credentials Service Principal will manage.

| Where | Role | Why |
|-------|------|-----|
| Azure RBAC (each subscription or resource group) | `Contributor` | Creates the Azure resources, for example the Communication Services resources. |
| Azure RBAC (same scopes) | `Owner`, `User Access Administrator` or `Role Based Access Control Administrator` | `Contributor` cannot write role assignments, and this layer assigns `Contributor` to the Dynamic Credentials Service Principal. |
| Microsoft Entra ID | `Application Administrator`, `Cloud Application Administrator` or `Application Developer` | Creates the App Registration, the Service Principal and the federated credentials. |
| Microsoft Entra ID | `Privileged Role Administrator` or `Global Administrator` | Grants the Microsoft Graph application permission `Application.ReadWrite.OwnedBy` to the Dynamic Credentials App Registration (admin consent). |
| State storage account | `Storage Blob Data Contributor` | Read and write the Terraform state in the Blob container. |
| TFE / HCP Terraform | Organization owner token | Creates the organization settings, project, workspaces and VCS connection. |

The Graph permission is not a nicety. The Dynamic Credentials App Registration later uses `Application.ReadWrite.OwnedBy` from inside `tfe-management` to create the federated credentials for each workspace. You can only grant it if you hold one of the Entra roles above.

## Before You Start: Values to Replace

Some values cannot be variables in Terraform and others are specific to the author's environment. Review this list **before** the first `terraform init`:

1. **Backend (`providers.tf`).** The `backend "azurerm"` block ships with the placeholders `<resource_group_name>`, `<storage_account_name>` and `<container_name>`. Backend blocks cannot use variables or expressions, so they must be hardcoded: replace them in the file, or pass real values at init time with `-backend-config=backend.hcl` (see [Step 1](#step-1-configure-azure-backend)).
2. **TFE hostname (`tfe_hostname`).** Set it in `terraform.tfvars`: `app.terraform.io` for **HCP Terraform**, or the FQDN of your instance for **self-hosted TFE** (e.g. `tfe.example.com`). The same applies wherever the README shows `app.terraform.io` (the `curl` check, the private registry module sources of the management repository).
3. **HCP Terraform vs. self-hosted TFE (SMTP).** The `tfe_admin_smtp_settings` resource is an instance-level setting of **self-hosted TFE** and has no effect on HCP Terraform. If you use HCP Terraform, remove the Azure Communication Services part: delete `azure-communication-services.tf`, the `tfe_admin_smtp_settings` block, the `data "azapi_resource" "email_domain"` and the `locals` in `organization-settings.tf`, the `# ACS info` outputs in `outputs.tf` and the `resource_group_name`, `smtp_username` and `smtp_test_email_address` variables.
4. **Module sources.** Every module `source` points at `git@github.com:permilche/...`. If you use your own copy of the modules, update each `source` (and its `ref`) by hand: sources cannot use variables. You also need an SSH key with read access to those repositories.
5. **VCS provider.** `workspace.tf` assumes Azure DevOps (`vcs_provider = "azure_devops"`). For another VCS provider adapt the `vcs_repo` blocks and create the OAuth client accordingly.
6. **Subscription keys.** The keys of `azure_subscriptions` (`subscription-a`, `subscription-b`) are literals in `providers.tf`, `workspace.tf`, `outputs.tf` and the `dynamic-credentials-azure-<name>.tf` files (provider aliases, module names, TAG-based variable names). Rename them or add your own as described in [Adding a new subscription](#why-module-blocks-cannot-be-dry).
7. **Azure Communication Services values.** `azure-communication-services.tf` hardcodes the region (`location = "spain-central"`), the data location (`"Europe"`) and the resource names (`tfe-notifications`). Change them to suit your environment. The resource group comes from `var.resource_group_name` and must already exist.
8. **Values without a default.** `resource_group_name` and the rest of the required variables have **no default on purpose**: you must provide them in `terraform.tfvars` (see `terraform.tfvars.example`).

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

> **Important: backend values cannot use variables.** Terraform's `backend` block is evaluated before the variable system is initialized, so expressions and `var.*` references are not allowed inside it. That is why `providers.tf` ships with the placeholders `<resource_group_name>`, `<storage_account_name>` and `<container_name>`, with a comment explaining it: **you must replace them** (they must be hardcoded, they cannot come from `terraform.tfvars`) and keep them in sync manually with any corresponding variables used elsewhere in the configuration. There are two ways to avoid the duplication:
>
> **Option A: `-backend-config` file (recommended for teams):** keep the placeholders in `providers.tf` and pass a separate file at init time (its values override the ones in the block):
> ```bash
> # backend.hcl  (already in .gitignore)
> resource_group_name  = "your-resource-group"
> storage_account_name = "your-storage-account"
> container_name       = "tfe-bootstrap-layer"
> key                  = "terraform.tfstate"
> ```
> ```bash
> terraform init -backend-config=backend.hcl
> ```
>
> **Option B: Terragrunt:** Terragrunt can template backend blocks before Terraform sees them, removing the duplication entirely. Worth considering if Terragrunt is already in the toolchain, but not worth introducing just for this.
>
> If neither approach fits, simply keep the values hardcoded in the `backend` block and treat the duplication as an accepted tradeoff. The backend config changes rarely.

### Step 2: Set Environment Variables

Set sensitive variables as environment variables:

```bash
# TFE Token
export TF_VAR_tfe_token="your-tfe-organization-token"
export TFE_TOKEN="your-tfe-organization-token"

# Azure Backend Authentication (if not using Azure CLI)
export ARM_ACCESS_KEY="your-storage-account-access-key"
# OR use Azure CLI authentication (recommended)
```

### Step 3: Create terraform.tfvars

Copy the example file and customize:

```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
organization_name  = "your-org-name"
organization_email = "your-admin-email@example.com"

tfe_hostname = "app.terraform.io" # HCP Terraform FQDN (use your own FQDN if self-hosted). The token is set via TF_VAR_tfe_token

vcs_oauth_token_id = "ot-xxxxxxxxxxxx"    # created manually in TFE UI (see Step 5)
vcs_https_url      = "https://dev.azure.com/your-org"
vcs_api_url        = "https://dev.azure.com/your-org"
vcs_organization   = "your-ado-org"
vcs_project        = "your-ado-project"
vcs_repository_management       = "tfe-management"
vcs_repository_private_registry = "tfe-private-registry"

vcs_branch_management       = "main"
vcs_branch_private_registry = "main"
terraform_version            = "1.5.0"
auto_apply                   = false

azure_subscriptions = {
  "your-subscription-name" = {
    subscription_id = "00000000-0000-0000-0000-000000000000"
    tenant_id       = "00000000-0000-0000-0000-000000000000"
  }
}
add_bootstrap_user_ownership = true # set to false if the creator is automatically added as app owner

# Azure Communication Services (SMTP)
resource_group_name     = "your-resource-group"
smtp_username           = "notifications"
smtp_test_email_address = "admin@example.com"

ssh_private_key = <<EOT
-----BEGIN RSA PRIVATE KEY-----
...
-----END RSA PRIVATE KEY-----
EOT
```

### Step 4: Initialize Terraform

```bash
# Option B: you already replaced the placeholders in providers.tf
terraform init

# Option A: real backend values in backend.hcl (see the Step 1 note above)
terraform init -backend-config=backend.hcl
```

This will:
- Download the TFE, azurerm, azuread, and azapi providers
- Download the modules from the `tfe-tf-modules` and `azure-tf-modules` Git repositories (over SSH)
- Configure the Azure backend
- Initialize the working directory

### Step 5: Plan and Apply

Review the planned changes:

```bash
terraform plan
```

Apply the configuration:

```bash
terraform apply
```

This will create:
- TFE organization settings (including SMTP via Azure Communication Services)
- Management project in TFE
- Management workspace in TFE (connected to Azure DevOps)
- Private registry workspace in TFE (connected to Azure DevOps, with SSH key)
- SSH key for private registry Git access
- Azure Dynamic Credentials base infrastructure (App Registration, Service Principal) per subscription
- Federated Identity Credentials for the management workspace (plan and apply phases)

> **Note on VCS OAuth (Azure DevOps):** With the `tfe` provider version used here (`~> 0.79.0`), the `tfe_oauth_client` resource can't create an OAuth client for Azure DevOps, so the `vcs-oauth.tf` file is fully commented out. Newer provider versions add Azure DevOps support (for example `ado_org_name` for Azure DevOps Services came in 0.82.0, check the provider changelog), so with one of them you should be able to manage the VCS integration as code too. Until then, you must:
> 1. Create the VCS OAuth connection manually in the TFE UI (*Settings → VCS Providers → Add VCS Provider*)
> 2. Enable OAuth Applications in Azure DevOps and create an App Registration in the same tenant
> 3. Retrieve the resulting OAuth token ID from the TFE UI
> 4. Pass that ID as `vcs_oauth_token_id` in `terraform.tfvars`

### Step 6: Verify Management Workspace

After successful apply, you'll see outputs including:

```
management_workspace_html_url = "https://app.terraform.io/app/<organization_name>/workspaces/tfe-management"
private_registry_workspace_html_url = "https://app.terraform.io/app/<organization_name>/workspaces/tfe-private-registry"
```

Visit these URLs to verify the workspaces were created correctly.

## Design Decisions and Alternatives

> **This bootstrap reflects one particular set of structural choices.** There is no single correct way to organize TFE dynamic credentials, App Registrations, or workspace layout. What follows documents the rationale behind the decisions made here, along with common alternatives. Different organizations will make different tradeoffs based on their security posture, team structure, and operational model.

### App Registration per subscription vs. shared App Registration

**This implementation:** one Azure App Registration and Service Principal per subscription.

**Alternative:** a single App Registration with RBAC assignments across multiple subscriptions (or even across all subscriptions at the Management Group level).

The single-App-Registration approach is simpler to configure. You only need one federated credential per workspace/run-phase, and one entry in the workspace's `TFC_AZURE_*` environment variables, regardless of how many subscriptions the workspace can reach. Some organizations prefer this because it reduces the number of App Registrations to maintain and makes access patterns easier to reason about at a glance.

The per-subscription approach was chosen here for:
- **Blast radius containment**: a compromised OIDC token only affects the one subscription its App Registration is scoped to
- **Principle of least privilege**: each App Registration can carry a different, minimal set of role assignments
- **Clean audit trail**: activity in each subscription is attributed to a distinct identity

Neither approach is universally correct. If your organization already manages cross-subscription access via Management Group RBAC, or if reducing the number of App Registrations is a higher priority than per-subscription isolation, the shared App Registration model is a perfectly valid choice.

### One bootstrap workspace vs. multiple bootstrap workspaces

**This implementation:** a single bootstrap layer that creates all workspaces (management and private registry) in one `terraform apply`.

**Alternative:** separate bootstrap configurations, one that creates the TFE organization and VCS connection, and further ones (or a management layer run) that create individual workspaces.

A single bootstrap is simpler initially but grows in scope as more workspaces are added. Splitting into multiple layers gives cleaner separation of concerns and allows different teams or automation pipelines to own different parts of the setup.

### Management workspace vs. managing everything from bootstrap

**This implementation:** the bootstrap layer is deliberately minimal. It creates the management workspace, which then takes over responsibility for all further TFE resources via a VCS-driven workflow.

**Alternative:** manage everything (projects, workspaces, variable sets, teams) directly from the bootstrap layer with local `terraform apply` runs.

The hand-off to a management workspace provides a full audit trail, peer review via pull requests, and eliminates the need for anyone to have local credentials for ongoing changes. The tradeoff is added complexity during initial setup and the need to re-run the bootstrap layer when onboarding new subscriptions (see [Operational Tradeoff](#operational-tradeoff-bootstrap-is-no-longer-run-once) below).

---

## Azure Dynamic Credentials Configuration

This bootstrap layer creates the **foundational** Azure Dynamic Credentials infrastructure: one Azure AD App Registration and Service Principal per target subscription, each with federated identity credentials scoped to the management workspace.

### How Dynamic Credentials Work

**Bootstrap Layer Responsibilities:**
1. Creates one Azure App Registration and Service Principal per subscription (via `dynamic-credentials-azure-configuration` module)
2. Creates federated identity credentials for the management workspace against each App Registration, for both `plan` and `apply` run phases (via `dynamic-credentials-azure-management` module)
3. Injects TAG-based `TFC_AZURE_*` and `ARM_*` environment variables into the management workspace so it can authenticate to each subscription independently

**Management Layer Responsibilities:**
1. Uses the `dynamic-credentials-azure-management` module to create federated credentials for application workspaces
2. Creates variable sets with the Application Client ID per subscription
3. Applies variable sets to workspaces that need dynamic credentials

### Multi-Subscription Architecture

This bootstrap layer uses **separate App Registrations per subscription** (not one shared App Registration with cross-subscription RBAC). See [Design Decisions and Alternatives](#design-decisions-and-alternatives) for the rationale and the alternative approach.

> **Same tenant only.** The `azurerm` and `azuread` providers of this layer authenticate against the single tenant of your Azure CLI session: no provider sets `tenant_id`, so every subscription in `azure_subscriptions` must belong to that tenant (the `tenant_id` field of the map is only used to build the `ARM_TENANT_ID_<TAG>` variables of the management workspace). Supporting several tenants would need an `azurerm` **and** an `azuread` provider alias per tenant passed to each module call, or, with full isolation, one bootstrap (repository and state) per tenant.
>
> **One Service Principal for several subscriptions** is the alternative described in [Design Decisions and Alternatives](#design-decisions-and-alternatives). It is possible because a Service Principal can hold role assignments in any subscription of its tenant, but each `azurerm` provider points at one subscription, so the extra assignments have to be created with an aliased provider for each additional subscription (the configuration module only assigns roles in the subscription of the provider it receives).

### File Layout

Each subscription gets its own `.tf` file containing everything that belongs to it: the `azurerm` provider alias, the configuration module, and the management module. This makes the set of subscriptions immediately visible from the file listing, and adding a new one means creating one new file rather than editing existing ones.

```
dynamic-credentials-azure-<subscription-name>.tf   # one per subscription
```

The `local.dynamic_credentials_azure_run_phases` used by all per-subscription management modules is defined once in the first file (`dynamic-credentials-azure-subscription-a.tf`).

### Why Module Blocks Cannot Be DRY

The natural instinct is to drive the provider and module blocks from a `for_each` over `var.azure_subscriptions`. This is a **hard Terraform limitation**:

- **Provider blocks** do not support `for_each` or any dynamic expression. Each `provider "azurerm"` block must be written out statically with a literal alias.
- **Module `providers =` argument** cannot use variable interpolation. `providers = { azurerm = azurerm.<alias> }` requires the alias to be a known static reference at plan time.

Because of these two constraints, the provider block, the configuration module, and the management module must each be written once per subscription. The `var.azure_subscriptions` map is still useful. It is the single source of truth for subscription IDs and tenant IDs referenced inside those blocks, keeping the *values* DRY even though the *structure* cannot be.

**Adding a new subscription checklist:**
1. Add an entry to `azure_subscriptions` in `terraform.tfvars`
2. Create a new `dynamic-credentials-azure-<name>.tf` file following the pattern of the existing ones (provider alias uses the map key as-is, e.g. `subscription-b`)
3. Add the corresponding `TFC_AZURE_*` / `ARM_*` TAG-based env variables **and** the per-subscription terraform variables (`tfc_application_id_<tag>`, `tfc_application_client_id_<tag>`, `az_subscription_id_<tag>`) in `workspace.tf`, use underscores in the TAG, never hyphens
4. Add the output in `outputs.tf`
5. Update the `tfe-management` `providers.tf` with an `azurerm` provider alias that **exactly matches** the TAG (e.g. `SUBSCRIPTION_A`)
6. Update the `tfe-management` `variables.tf` to declare the new per-subscription variables that will be injected

### Operational Tradeoff: Bootstrap Is No Longer Run-Once

The original goal of this bootstrap layer is to run it **once** at the beginning to establish the TFE organization and the management workspace, then hand off all further configuration to the management workspace itself via a VCS-driven workflow.

The multi-subscription dynamic credentials pattern breaks that assumption. Every time a new subscription needs to be onboarded, someone must:

1. Edit this repository (add a `.tf` file, update `terraform.tfvars`)
2. Run `terraform apply` locally from this bootstrap layer

This is because **the OIDC trust has to be established before TFE can use dynamic credentials for that subscription**. Specifically, the following must exist in Azure before the management workspace can authenticate to a new subscription:
- An App Registration and Service Principal in the tenant
- Federated Identity Credentials on that App Registration that name the exact TFE organization, project, workspace, and run phase
- Role assignments on the subscription for that Service Principal

All of that is what this bootstrap layer creates. The management workspace cannot create these for itself because it needs them to already exist in order to authenticate and run.

#### Alternative: Static Credentials in the Management Layer

If re-running the bootstrap layer for every new subscription is undesirable, the alternative is to **bypass this bootstrap entirely for new subscriptions** and instead configure static Azure credentials (a client secret or certificate) directly in the `tfe-management` workspace for the new subscription. The management workspace can then create the App Registration, federated credentials, and role assignments for *application* workspaces dynamically. It just authenticates to the new subscription via static credentials rather than OIDC for that initial setup step.

The tradeoff:

| Approach | Bootstrap involvement | Credential type in management layer | Notes |
|---|---|---|---|
| **Dynamic credentials (this layer)** | Required per new subscription | OIDC, no secrets stored | More secure, but bootstrap must be re-run |
| **Static credentials** | Not required | Client secret / certificate | Simpler to extend, but a secret must be stored and rotated in TFE |

The right choice depends on the organization's security posture, how frequently new subscriptions are added, and whether re-running the bootstrap layer fits the operational model. Both are valid. The decision is left to the consumer of these modules.

### Provider Configuration

A default (no-alias) `azurerm` provider is configured in `providers.tf` pointing at the primary subscription. This is used by resources that are not subscription-specific (e.g. Azure Communication Services). Each subscription additionally has its own aliased provider in its per-subscription file.

```hcl
# providers.tf: default provider for shared resources
provider "azurerm" {
  subscription_id = var.azure_subscriptions["<primary-subscription>"].subscription_id
  features {}
}

# dynamic-credentials-azure-<name>.tf: one per subscription
provider "azurerm" {
  alias           = "<subscription-name>"    # e.g. "subscription-a"
  subscription_id = var.azure_subscriptions["<subscription-name>"].subscription_id
  features {}
}
```

### TAG-Based Environment Variables

TFE supports multiple dynamic credential configurations in a single workspace via environment variable TAGs. The TAG suffix (derived from the map key by replacing hyphens with underscores and uppercasing) identifies the provider alias in the management workspace. See the [TFE documentation](https://developer.hashicorp.com/terraform/enterprise/dynamic-provider-credentials/azure-configuration#required-environment-variables) for full details.

```
TFC_AZURE_PROVIDER_AUTH_<TAG>  = "true"
TFC_AZURE_RUN_CLIENT_ID_<TAG>  = "<client-id-for-this-subscription>"
ARM_SUBSCRIPTION_ID_<TAG>      = "<subscription-id>"
ARM_TENANT_ID_<TAG>            = "<tenant-id>"
```

These variables are set on the management workspace in `workspace.tf`, one group per subscription.

> **⚠️ Critical naming constraint: hyphens are not allowed in TAGs.**
>
> The `TFC_AZURE_PROVIDER_AUTH_<TAG>` family of environment variables uses the TAG as a suffix in an environment variable name. Environment variable names **cannot contain hyphens** (`-`). This means:
>
> - Map keys like `"subscription-a"` must be translated to `SUBSCRIPTION_A` (hyphens → underscores, uppercased) when used as a TAG.
> - The provider `alias` declared in the `tfe-management` `providers.tf` **must exactly match the TAG:** same case, same separators, or TFE will not map the dynamic credential to the correct provider. There is no automatic normalization.
>
> Note that the provider alias in **this bootstrap layer** (e.g. `azurerm.subscription-a`) does not need to match the TAG. It is only used internally within this bootstrap configuration. The TAG constraint applies to the **management layer** provider alias.
>
> **Example: bootstrap (`workspace.tf`):**
> ```hcl
> "TFC_AZURE_PROVIDER_AUTH_SUBSCRIPTION_A" = { category = "env", value = "true" }
> "TFC_AZURE_RUN_CLIENT_ID_SUBSCRIPTION_A" = { category = "env", value = "..." }
> ```
>
> **Example: tfe-management (`providers.tf`), alias must match the TAG exactly:**
> ```hcl
> provider "azurerm" {
>   alias           = "SUBSCRIPTION_A"   # must be SUBSCRIPTION_A, not subscription-a or subscription_a
>   subscription_id = var.az_subscription_id_subscription_a
>   features {}
> }
> ```
>
> If the alias in `tfe-management` does not match the TAG exactly, the run will fail with an authentication error because TFE looks up credentials by the literal alias string.

### Adding Custom Roles to the Service Principal

The Service Principal's role assignments are configured in the `dynamic-credentials-azure-configuration` module. To add custom roles, modify the module's configuration or pass appropriate parameters.

Refer to the module's documentation for available parameters to configure role assignments.

### Dynamic Credentials Testing

In application workspace code, no special provider configuration is needed. The management layer injects the correct environment variables automatically:

```hcl
provider "azurerm" {
  features {}
}
```

To verify dynamic credentials are working end-to-end:

```hcl
provider "azurerm" {
  features {}
}

resource "null_resource" "this" {
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "env"  # prints all env vars set by TFE, including ARM_* and TFC_AZURE_*
  }
}

data "azurerm_client_config" "current" {}

output "client_id" {
  value = data.azurerm_client_config.current.client_id
}
```

---

## Azure Communication Services Configuration

> **Self-hosted TFE only.** The SMTP settings are an instance-level setting of self-hosted TFE and have no effect on HCP Terraform. If you use HCP Terraform, remove this part as described in [Before You Start](#before-you-start-values-to-replace).

This bootstrap layer optionally configures Azure Communication Services for TFE email notifications via SMTP. This setup creates the necessary Azure resources to enable TFE to send notification emails.

### Architecture

The configuration uses two modules to set up email capabilities:

1. **Email Service Module** (`avm-res-communication-emailservice`): Creates the Azure Communication Services Email Service with an Azure-managed domain
2. **Communication Service Module** (`azure-communication-service`): Creates the Communication Service, links it to the email domain, and sets up SMTP authentication via an Entra ID application

### Configuration

The setup is defined in `azure-communication-services.tf`:

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

The SMTP credentials (`smtp_username` and the sensitive `smtp_password`) are outputs of the `azure-communication-service` **module**. They are **not** re-exported by this layer, so they never show up in `terraform output`. They are consumed directly by the `organization-settings` module (see below).

### Integration with TFE

In [`organization-settings.tf`](organization-settings.tf), the SMTP settings are wired directly from the module outputs, through the `tfe_admin_smtp_settings` input of the `organization-settings` module:

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

The `smtp_sender_domain` local is resolved via a `data "azapi_resource"` block that reads the Azure-managed domain name from the email service (since the AVM module does not expose it as an output directly).

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

---

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
├── variable-sets.tf     # Variable set configurations
├── dynamic-credentials.tf  # Workspace-specific federated credentials
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
  # TFE_TOKEN added in the management workspace/s as an env variable to be able to create and manage TFE resources
  hostname = var.tfe_hostname # injected by the bootstrap layer (app.terraform.io for HCP Terraform)
}

provider "azurerm" {
  features {}
  # Uses dynamic credentials from bootstrap layer
}
```

Example `dynamic-credentials.tf` for creating workspace-specific credentials:

```hcl
# One federated credential per workspace and run phase (the module manages a single credential, so use for_each)
module "dynamic_creds_app_workspaces" {
  source   = "app.terraform.io/<organization_name>/dynamic-credentials-azure-management/tfe" # cannot use variables there so need to hardcode it
  for_each = local.dynamic_credentials # map of { organization, project, workspace, run_phase }

  providers = {
    azuread = azuread
  }

  tfc_application_id = var.tfc_application_id_subscription_a # From the bootstrap-injected variables
  tfc_hostname       = var.tfe_hostname
  organization       = each.value.organization
  project            = each.value.project
  workspace          = each.value.workspace
  run_phase          = each.value.run_phase # "plan" or "apply"
  display_name       = each.key
}
```

### 4. Configure Workspace Variables

The management workspace has these variables injected by bootstrap (from `workspace.tf`):

**Shared variables (one per organization):**
- `organization`: TFE organization name
- `tfe_token`: TFE API token
- `tfe_hostname`: TFE hostname
- `vcs_org`: Azure DevOps organization name
- `vcs_oauth_token_id`: OAuth token ID for VCS connections
- `vcs_project`: Azure DevOps project name
- `az_tenant_id`: Azure Tenant ID (shared across all subscriptions)

**Per-subscription variables (one set per subscription, named with the TAG suffix):**
- `tfc_application_id_<tag>`: App Registration object ID (used by the dynamic-credentials-azure-management module to create federated credentials for downstream workspaces)
- `tfc_application_client_id_<tag>`: App Registration client ID (injected into downstream workspace variable-sets)
- `az_subscription_id_<tag>`: Azure Subscription ID

For example, for subscription `subscription-a` (TAG = `SUBSCRIPTION_A`):
- `tfc_application_id_subscription_a`
- `tfc_application_client_id_subscription_a`
- `az_subscription_id_subscription_a`

> **Note:** The variable names use lowercase underscores (`subscription_a`) while the TAG-based environment variables use uppercase (`SUBSCRIPTION_A`). Both derive from the same map key by replacing hyphens with underscores. The difference is only in casing. The `tfe-management` `variables.tf` must declare matching variable names for all per-subscription values listed above.

### 5. Push and Trigger

```bash
git add .
git commit -m "Initial TFE configuration"
git push origin main
```

Once the private registry modules are published, queue the first `tfe-management` run manually in the UI (see the note at the start of this section). From then on, pushes trigger runs automatically.

---

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
- **dynamic-credentials-azure-management**: Create workspace-specific federated credentials
- **policy-set**: Enforce governance policies
- **run-task**: Integrate security/cost tools

---

## State Management

### Bootstrap Layer (This Directory)
- **Backend**: Azure Blob Storage
- **State File**: `terraform.tfstate` in configured container
- **Management**: Manual Terraform commands (terraform plan/apply)

### Management Workspace (TFE)
- **Backend**: TFE managed state
- **State File**: Managed automatically by TFE
- **Management**: VCS-driven workflow (automatic runs on git push)

---

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
curl -H "Authorization: Bearer $TFE_TOKEN" \
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

### Issue: Dynamic credentials not working

- Verify the Application Registration exists in Azure AD
- Check that Federated Identity Credentials are configured correctly
- Ensure the Service Principal has the required role assignments
- Verify environment variables are set correctly in the workspace
- Check that the workspace is using the correct Application Client ID

### Issue: Data source error

```bash
│ Error: Resource not found
│
│   with data.azapi_resource.email_domain,
│   on organization-settings.tf line 29, in data "azapi_resource" "email_domain":
│   29: data "azapi_resource" "email_domain" {
│
│ resource "Resource: (ResourceId
│ \"/subscriptions/<subscription-id>/resourceGroups/<resource-group>/providers/Microsoft.Communication/emailServices/tfe-notifications/domains/AzureManagedDomain\"
│ / Api Version \"2023-04-01\")" not found
```
You might encounter this on the first apply since the resources do not exist yet. Re-apply to get rid of it. We could remove this resource if the avm-res-communication-emailservice module exposed that as an output.

### Issue: Error creating AdminSMTP Settings

```bash
│ Error: Error creating AdminSMTP Settings
│
│   with module.organization_settings.tfe_admin_smtp_settings.this[0],
│   on .terraform/modules/organization_settings/organization-settings/main.tf line 39, in resource "tfe_admin_smtp_settings" "this":
│   39: resource "tfe_admin_smtp_settings" "this" {
│
│ Could not set Admin SMTP Settings, unexpected error: failed to update Admin SMTP Settings: unauthorized
```
Seen this some times, re-apply to get rid of it.

### Issue: Error creating graph permissions for Azure Dynamic Credentials

```bash
│ Error: Could not create app role assignment
│
│   with module.dynamic_credentials_azure_configuration.azuread_app_role_assignment.tfc_graph_permissions,
│   on .terraform/modules/dynamic_credentials_azure_configuration/dynamic-credentials/azure/configuration/main.tf line 89, in resource "azuread_app_role_assignment" "tfc_graph_permissions":
│   89: resource "azuread_app_role_assignment" "tfc_graph_permissions" {
│
│ unexpected status 403 (403 Forbidden) with error: Authorization_RequestDenied: Insufficient privileges to complete
│ the operation.
```
The user running `tfe-bootstrap` (the identity you are authenticated as in Azure CLI) must be allowed to grant `Application.ReadWrite.OwnedBy` to the Dynamic Credentials App Registration. That same App Registration later uses this permission to create the dynamic credentials for itself. See [Permissions Required to Run This Layer](#5-permissions-required-to-run-this-layer) for the Entra roles that can do this.

---

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
- Management workspace and private registry workspace
- Bootstrap project
- SSH key for private registry
- VCS OAuth connection
- Organization settings
- Azure Dynamic Credentials infrastructure (App Registrations, Service Principals, Federated Identity Credentials)

---

## Security Best Practices

1. **Never commit sensitive values** to version control
2. **Use environment variables** for tokens and secrets
3. **Enable MFA** on TFE accounts
4. **Rotate tokens regularly**
5. **Use least-privilege access** for service accounts
6. **Enable audit logging** in TFE
7. **Review workspace permissions** regularly
8. **Use dynamic credentials** instead of static credentials where possible
9. **Limit Service Principal permissions** to minimum required roles
10. **Separate credentials per environment** for production workloads

---

## Support

This project is offered as is and **no support is provided** (see the disclaimer at the top of this README and [SUPPORT](.github/SUPPORT.md)). For issues or questions, these resources are the best place to start:

- The README of each module used here, in [`tfe-tf-modules`](https://github.com/permilche/tfe-tf-modules) and [`azure-tf-modules`](https://github.com/permilche/azure-tf-modules)
- [TFE documentation](https://developer.hashicorp.com/terraform/enterprise)
- [TFE provider documentation](https://registry.terraform.io/providers/hashicorp/tfe/latest/docs)
- [Azure dynamic credentials documentation](https://developer.hashicorp.com/terraform/enterprise/dynamic-provider-credentials/azure-configuration)

## License

Licensed under the [Mozilla Public License 2.0](LICENSE). See also [CONTRIBUTING](.github/CONTRIBUTING.md), [SUPPORT](.github/SUPPORT.md) and [SECURITY](.github/SECURITY.md).

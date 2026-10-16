# Identity used by the CI pipeline to run `terraform plan` (ADR-006).
# It has no secret: GitHub proves who it is with a signed OIDC token, and the
# federated credential below decides which tokens are accepted.

resource "azurerm_resource_group" "cicd" {
  name     = "rg-securenet-cicd-dev-eus-001"
  location = var.location
  tags     = local.monitoring_tags
}

# A user-assigned managed identity cannot hold a client secret, so a
# long-lived password can never be added to it later.
resource "azurerm_user_assigned_identity" "ci" {
  name                = "id-securenet-ci-dev-eus-001"
  location            = azurerm_resource_group.cicd.location
  resource_group_name = azurerm_resource_group.cicd.name
  tags                = local.monitoring_tags
}

# Trust rule: accept tokens signed by GitHub only for pull requests of this
# repository. The subject uses GitHub's immutable owner and repository IDs, so
# a repository re-created later with the same name does not match.
resource "azurerm_federated_identity_credential" "github_pull_requests" {
  name                = "github-pull-requests"
  resource_group_name = azurerm_resource_group.cicd.name
  parent_id           = azurerm_user_assigned_identity.ci.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:jeromendezb@294006608/azure-securenet-foundation@1374980134:pull_request"
}

# Read every resource to compare it with the code. Cannot change anything.
resource "azurerm_role_assignment" "ci_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.ci.principal_id
}

# The state storage account is created by scripts/bootstrap-state.ps1, not by
# Terraform (ADR-005). Its ID is built from its name instead of a data source:
# the storage account data source reads the account keys, which a read-only
# identity is not allowed to do, so it would break the plan in CI.
locals {
  tfstate_storage_account_id = "${data.azurerm_subscription.current.id}/resourceGroups/rg-securenet-tfstate-dev-eus-001/providers/Microsoft.Storage/storageAccounts/stsecurenettfstate001"
}

# `plan` takes a lock on the state file, and taking the lock is a write.
resource "azurerm_role_assignment" "ci_state" {
  scope                = local.tfstate_storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.ci.principal_id
}

output "ci_client_id" {
  description = "Client ID of the CI identity. Stored in GitHub Actions secrets as AZURE_CLIENT_ID so it is masked in the public logs; it is not a credential."
  value       = azurerm_user_assigned_identity.ci.client_id
}
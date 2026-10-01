data "azurerm_subscription" "current" {}

# Built-in definition: "Azure Key Vault should disable public network access".
# Referenced by its GUID, which is the same in every tenant and never changes.
data "azurerm_policy_definition" "kv_public_access" {
  name = "405c5871-3e91-4644-8a63-58e19d68ff5b"
}

# Assigned at subscription scope: a guardrail must cover vaults created anywhere,
# not only the ones this repository deploys. Kept outside the workload so that
# destroying the lab never removes it.
resource "azurerm_subscription_policy_assignment" "kv_public_access" {
  name                 = "kv-disable-public-access"
  display_name         = "Key Vaults must disable public network access (SEC-015)"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = data.azurerm_policy_definition.kv_public_access.id

  parameters = jsonencode({
    effect = { value = var.kv_public_access_effect }
  })
}
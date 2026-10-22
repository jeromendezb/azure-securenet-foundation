# Team access to workload resources (TKT-004). Declared here so the role
# assignments are recreated with every apply after a destroy.

data "azurerm_subscription" "team_access" {}

# The role is defined once in governance/; the workload only assigns it.
data "azurerm_role_definition" "vm_operator" {
  name  = "SecureNet VM Operator"
  scope = data.azurerm_subscription.team_access.id
}

resource "azurerm_role_assignment" "operators_vm_operator" {
  scope              = azurerm_resource_group.main.id
  role_definition_id = data.azurerm_role_definition.vm_operator.id
  principal_id       = var.operators_group_object_id
  principal_type     = "Group"
}

resource "azurerm_role_assignment" "developers_vm_app_reader" {
  scope                = azurerm_linux_virtual_machine.app.id
  role_definition_name = "Reader"
  principal_id         = var.developers_group_object_id
  principal_type       = "Group"
}
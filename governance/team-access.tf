# Custom role for operators (TKT-004): read, start and restart VMs, nothing
# else. Virtual Machine Contributor would also allow run-command, which runs
# scripts as root on the VM.
resource "azurerm_role_definition" "vm_operator" {
  name        = "SecureNet VM Operator"
  scope       = data.azurerm_subscription.current.id
  description = "Read, start and restart virtual machines. No run-command and no configuration changes."

  permissions {
    actions = [
      "Microsoft.Compute/virtualMachines/read",
      "Microsoft.Compute/virtualMachines/instanceView/read",
      "Microsoft.Compute/virtualMachines/start/action",
      "Microsoft.Compute/virtualMachines/restart/action",
    ]
  }

  assignable_scopes = [data.azurerm_subscription.current.id]
}

# Operators watch the monitoring layer, which is never destroyed with the lab.
resource "azurerm_role_assignment" "operators_monitoring_reader" {
  scope                = azurerm_resource_group.monitoring.id
  role_definition_name = "Monitoring Reader"
  principal_id         = var.operators_group_object_id
  principal_type       = "Group"
}

# Developers query logs in the workspace, read-only.
resource "azurerm_role_assignment" "developers_log_analytics_reader" {
  scope                = azurerm_log_analytics_workspace.main.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = var.developers_group_object_id
  principal_type       = "Group"
}
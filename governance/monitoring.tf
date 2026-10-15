locals {
  monitoring_tags = {
    project     = "securenet"
    environment = "dev"
    owner       = "jeromendezb"
    managed_by  = "terraform"
    layer       = "monitoring"
  }
}

# Long-lived monitoring layer (ADR-004). It lives outside the workload root so
# that destroying the lab never deletes the logs that explain what happened.
resource "azurerm_resource_group" "monitoring" {
  name     = "rg-securenet-monitoring-dev-eus-001"
  location = var.location
  tags     = local.monitoring_tags
}

# 90 days of retention are included at no charge once Microsoft Sentinel is enabled.
resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-securenet-dev-eus-001"
  location            = azurerm_resource_group.monitoring.location
  resource_group_name = azurerm_resource_group.monitoring.name
  sku                 = "PerGB2018"
  retention_in_days   = 90

  # Shared keys would let anyone holding them write data without an Entra ID
  # identity, which could be used to inject fake logs. Only Entra ID is allowed.
  local_authentication_disabled = true

  # Lab only: caps cost at 1 GB/day. When the cap is reached, ingestion stops
  # until the next day, so production would use no cap plus a budget alert.
  daily_quota_gb = 1

  tags = local.monitoring_tags

}

# Sends the subscription Activity Log to the workspace so it can be queried with
# KQL and used by analytics rules. Run-command executions are recorded in the
# Administrative category. AzureActivity ingestion is free, so every category
# is enabled; declaring all of them also avoids a perpetual diff.
resource "azurerm_monitor_diagnostic_setting" "activity_log" {
  name                       = "diag-activity-log-to-law"
  target_resource_id         = data.azurerm_subscription.current.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id

  enabled_log {
    category = "Administrative"
  }

  enabled_log {
    category = "Security"
  }

  enabled_log {
    category = "ServiceHealth"
  }

  enabled_log {
    category = "Alert"
  }

  enabled_log {
    category = "Recommendation"
  }

  enabled_log {
    category = "Policy"
  }

  enabled_log {
    category = "Autoscale"
  }

  enabled_log {
    category = "ResourceHealth"
  }
}
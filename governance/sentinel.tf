# Enables Microsoft Sentinel on the monitoring workspace (ADR-004). Sentinel is
# not a separate store: it reads the logs already in the workspace and runs the
# analytics rules defined in this file.
# The 31-day free trial (10 GB/day) starts when this is applied, so lab tests
# with the full environment deployed must happen within that window.
resource "azurerm_sentinel_log_analytics_workspace_onboarding" "main" {
  workspace_id = azurerm_log_analytics_workspace.main.id
}
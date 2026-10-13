# Enables Microsoft Sentinel on the monitoring workspace (ADR-004). Sentinel is
# not a separate store: it reads the logs already in the workspace and runs the
# analytics rules defined in this file.
# The 31-day free trial (10 GB/day) starts when this is applied, so lab tests
# with the full environment deployed must happen within that window.
resource "azurerm_sentinel_log_analytics_workspace_onboarding" "main" {
  workspace_id = azurerm_log_analytics_workspace.main.id
}

# Detects every VM run-command, successful or failed (ADR-004). Run-command
# executes scripts as root through the VM agent, bypassing NSGs and Bastion,
# so a single execution is worth reviewing. Legitimate uses (test scripts and
# break-glass) always have a ticket; triage checks for one.
resource "azurerm_sentinel_alert_rule_scheduled" "vm_run_command" {
  name                       = "alert-run-command-executed"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.main.workspace_id
  display_name               = "Run Command executed (SEC-016)"
  description                = "A script was run, or attempted, as root on a VM through run-command. Check for an open ticket (test or break-glass incident) that explains it. If there is none, treat it as an incident."
  enabled                    = true
  severity                   = "High"
  tactics                    = ["Execution"]

  query = <<-QUERY
    AzureActivity
    | where OperationNameValue =~ "MICROSOFT.COMPUTE/VIRTUALMACHINES/RUNCOMMAND/ACTION"
    | where ActivityStatusValue in ("Success", "Failure")
    | project TimeGenerated, Caller, CallerIpAddress, ActivityStatusValue, _ResourceId
  QUERY

  query_frequency   = "PT5M"
  query_period      = "PT5M"
  trigger_operator  = "GreaterThan"
  trigger_threshold = 0
}
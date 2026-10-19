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

  # Entities: who ran the command, from which IP, on which VM (SEC-017).
  # Each column_name must be a column this rule's query returns.
  entity_mapping {
    entity_type = "Account"
    field_mapping {
      identifier  = "FullName"
      column_name = "Caller"
    }
  }

  entity_mapping {
    entity_type = "IP"
    field_mapping {
      identifier  = "Address"
      column_name = "CallerIpAddress"
    }
  }

  entity_mapping {
    entity_type = "AzureResource"
    field_mapping {
      identifier  = "ResourceId"
      column_name = "_ResourceId"
    }
  }
}

# Detects repeated Key Vault access denials from the same identity (ADR-004).
# A single 403 is usually a misconfiguration (for example, a missing DNS link),
# so the rule only fires when one identity is denied 5 or more times in
# 10 minutes, which points to probing with a stolen identity.
resource "azurerm_sentinel_alert_rule_scheduled" "kv_repeated_denials" {
  name                       = "alert-kv-repeated-denials"
  log_analytics_workspace_id = azurerm_sentinel_log_analytics_workspace_onboarding.main.workspace_id
  display_name               = "Repeated Key Vault access denials (SEC-016)"
  description                = "One identity was denied access to a Key Vault 5 or more times in 10 minutes. Check whether a recent change broke its network path or its role. If neither explains it, treat it as probing with a compromised identity."
  enabled                    = true
  severity                   = "Medium"
  tactics                    = ["CredentialAccess"]

  query = <<-QUERY
    AzureDiagnostics
    | where ResourceProvider == "MICROSOFT.KEYVAULT" and Category == "AuditEvent"
    | where httpStatusCode_d == 403
    | extend Identity = coalesce(column_ifexists("identity_claim_upn_s", ""), tostring(identity_claim_oid_g), CallerIPAddress)
    | summarize Denials = count(), DistinctIPs = dcount(CallerIPAddress), FirstSeen = min(TimeGenerated), LastSeen = max(TimeGenerated), CallerIPs = make_set(CallerIPAddress), VaultId = take_any(_ResourceId) by Identity, Resource
    | where Denials >= 5
    | extend FirstCallerIP = tostring(CallerIPs[0])
  QUERY

  query_frequency   = "PT10M"
  query_period      = "PT10M"
  trigger_operator  = "GreaterThan"
  trigger_threshold = 0

  # Entities: who was denied, from which IP, on which vault (SEC-017).
  # The summarize drops the raw columns, so these map to the columns it creates.
  entity_mapping {
    entity_type = "Account"
    field_mapping {
      identifier  = "FullName"
      column_name = "Identity"
    }
  }

  entity_mapping {
    entity_type = "IP"
    field_mapping {
      identifier  = "Address"
      column_name = "FirstCallerIP"
    }
  }

  entity_mapping {
    entity_type = "AzureResource"
    field_mapping {
      identifier  = "ResourceId"
      column_name = "VaultId"
    }
  }
}
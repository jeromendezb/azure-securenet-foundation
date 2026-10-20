# Evidence: Defender for Cloud recommendations triage

**Date:** 2026-10-19
**Objective:** Review the free foundational CSPM recommendations for the
subscription and decide, for each one, whether to fix it or accept it.

## Method

Unhealthy assessments read from Azure Resource Graph:

```
az graph query -q "securityresources
  | where type == 'microsoft.security/assessments'
  | where properties.status.code == 'Unhealthy'
  | extend recurso = tostring(split(properties.resourceDetails.Id, '/')[-1]),
           recomendacion = tostring(properties.displayName),
           severidad = tostring(properties.metadata.severity)
  | extend orden = case(severidad == 'High', 1, severidad == 'Medium', 2, 3)
  | order by orden asc
  | project severidad, recurso, recomendacion" --first 50 --query "data" -o table
```

The workload had been deployed a few hours earlier. Defender had not yet
assessed the VMs or the Key Vault, so only long-lived resources appear.

## Triage

| # | Severity | Resource | Recommendation | Decision |
|---|---|---|---|---|
| 1 | High | `<subscription>` | Microsoft Defender for Resource Manager should be enabled | Accepted: paid plan. The Sentinel run-command rule covers part of control-plane abuse |
| 2 | High | `<subscription>` | Microsoft Defender for Storage plan should be enabled with Malware Scanning and Sensitive Data Threat Detection | Accepted: paid plan. The only storage account holds Terraform state, with Entra ID-only access and versioning |
| 3 | High | `<subscription>` | There should be more than one owner assigned to subscriptions | Accepted for the lab: one operator. Production: at least two owners plus a break-glass account, with PIM |
| 4 | High | `<subscription>` | Microsoft Defender CSPM should be enabled | Accepted: paid plan. The free CSPM produced this list |
| 5 | Medium | `<subscription>` | Email notification to subscription owner for high severity alerts should be enabled | Fix (SEC-021) |
| 6 | Medium | `stsecurenettfstate001` | Storage account should use a private link connection | Known limitation ([ADR-005](../adr/adr-005-remote-state.md)): Terraform runs from the workstation and from CI over the Internet |
| 7 | Medium | `stsecurenettfstate001` | Storage accounts should restrict network access using virtual network rules | Known limitation, same cause as #6 |
| 8 | Low | `<subscription>` | Subscriptions should have a contact email address for security issues | Fix (SEC-021) |
| 9 | Low | `<subscription>` | Email notification for high severity alerts should be enabled | Fix (SEC-021) |

## Findings

1. **Three recommendations, one fix.** #5, #8 and #9 are the same missing
   setting: a security contact with alert notifications. Today a High alert
   from Defender reaches no one.
2. **Four of nine require paid plans.** Free CSPM reports the absence of paid
   protection as High severity. Each was decided on cost, with the
   compensating control named.
3. **New resources are not assessed immediately.** The lab's VMs and Key Vault
   did not appear a few hours after deployment. Assessing them requires the
   workload to stay deployed longer than one lab session.
# ADR-004: Detection with Microsoft Sentinel in a persistent monitoring layer

- **Status:** Accepted
- **Date:** 2026-10-13
- **Deciders:** Jero Méndez
- **Supersedes:** —
- **Superseded by:** —

## Context

Security finding SEC-016 (issue #21) reports that the environment prevents
several attack paths but does not detect attempts against them. Two events
have high value and produce no alert today:

1. **Key Vault access denials (403).** The vault already sends its
   `AuditEvent` logs to a Log Analytics workspace, but no rule reviews them.
2. **VM run-command execution.** `az vm run-command` runs a script as root
   through the VM agent, with no network path, no SSH and no NSG in between.
   The only requirement is an Azure role that includes
   `Microsoft.Compute/virtualMachines/runCommand/action`. It is the documented
   break-glass path, which also makes it the most direct path for an attacker
   with a stolen identity. The event is recorded only in the Activity Log,
   which is not sent to any workspace. During the break-glass test it could
   only be found with a manual query, and that query silently returned 1 of 6
   events because of the CLI's 50-event default.

There is also a lifecycle problem. The Log Analytics workspace is defined in
the main Terraform root, which is destroyed at the end of every lab session.
Every destroy deletes the logs with it. In a real incident, an attacker who
deletes the infrastructure would delete the evidence at the same time.

## Decision

### 1. The monitoring layer lives in `governance/`

The Log Analytics workspace, the subscription Activity Log diagnostic setting,
Microsoft Sentinel and its analytics rules move to the `governance/` root, in
their own resource group. That root is long-lived and is not destroyed with
the workload.

The Key Vault diagnostic setting stays in the main root, because it belongs to
the vault and should be removed with it. It finds the workspace through a
`data` source instead of creating it.

The monitoring layer must outlive the resources it monitors.

### 2. Microsoft Sentinel instead of Azure Monitor alert rules

Sentinel is enabled on the workspace, and detections are written as scheduled
analytics rules.

### 3. Detection rules

| Rule | Logic | Severity | Triage question |
|---|---|---|---|
| VM run-command executed | Every successful `RUNCOMMAND/ACTION` in `AzureActivity` | High | Is there an open ticket (test or break-glass incident) that explains this execution? If not, treat it as an incident. |
| Repeated Key Vault denials | 5 or more `403` responses from the same caller identity within 10 minutes | Medium | Is this identity known? Did a recent change break its network path or its role? If neither, treat it as probing. |

## Alternatives considered

### 1. Keep the workspace in the main root

Rejected. Logs are deleted on every destroy, and the evidence has the same
lifecycle as the attack surface.

### 2. A third Terraform root dedicated to monitoring

Deferred. It would separate preventive controls (Policy) from detective
controls (Sentinel) more cleanly. At the current size, `governance/` already
holds the long-lived, subscription-scoped controls, and a third root adds
state and apply-order overhead without a clear benefit. To revisit if the
monitoring layer grows.

### 3. Azure Monitor scheduled query alerts instead of Sentinel

Rejected for this lab, kept as a fallback. They are cheaper and simpler, but
they produce notifications, not incidents: no status, owner, severity
workflow or entity mapping. Sentinel is also the tool used in the security
operations roles this project targets.

### 4. Alert on every Key Vault 403

Rejected. A single misconfiguration produces a 403 on every retry. During the
private endpoint test (SEC-014), the missing DNS zone VNet link made `vm-app`
receive a 403 on every attempt, with no attacker involved. One alert per 403
leads to alert fatigue, and an ignored alert is the same as no alert.

## Consequences

### Positive

- Logs survive `terraform destroy` of the workload.
- Both detections are queryable with KQL and produce incidents with a triage
  step, instead of depending on someone running a manual CLI query.
- Cost is measured, not assumed:
  - `AzureActivity` ingestion is free in Log Analytics and in Sentinel.
  - Sentinel's free trial covers the first 10 GB/day for 31 days.
  - Key Vault `AuditEvent` logs are the only billable data after the trial,
    and the lab's volume is in kilobytes.

### Negative

- **Apply order dependency.** `governance/` must be applied before the main
  root, or the Key Vault diagnostic setting cannot find the workspace.
  Mitigation: documented in the README; the `data` source fails the plan with
  a clear error if the workspace is missing.
- **A billable resource is always on.** Mitigation: the workspace has no cost
  without ingestion, and the only billable source is the Key Vault, which only
  exists during lab sessions.
- **The run-command rule depends on ticket discipline.** Legitimate uses (test
  scripts and break-glass) also trigger it. Mitigation: every test that uses
  run-command references its issue, so triage is a lookup, not a guess.
- **The 403 threshold is a starting point.** Five denials in ten minutes is a
  conservative initial value, not a measured baseline. In production it would
  be tuned with real data.
- **Sentinel's management experience is moving to the Microsoft Defender
  portal.** Azure portal support is announced until March 31, 2027. Rules are
  defined in Terraform, so the portal change does not affect them.

## Future work

- Automation rule to notify by email when an incident is created.
- Detection on Policy denials (`RequestDisallowedByPolicy`) as a signal of
  attempts to create non-compliant resources.
- Tune the 403 threshold after collecting a baseline.
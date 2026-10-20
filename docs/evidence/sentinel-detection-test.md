# Evidence: Sentinel detection of run-command and Key Vault denials

**Date:** 2026-10-15
**Issue:** #21 (SEC-016)
**Objective:** Verify that both Sentinel analytics rules create an incident
from a real event, and that each incident can be triaged with the data it
carries.

Times are in UTC. The operator's local time is UTC-5.

## Setup

Monitoring layer in `governance/` ([ADR-004](../adr/adr-004-detection-with-sentinel.md)),
deployed before the workload and not destroyed with it:

- Log Analytics workspace `log-securenet-dev-eus-001` in
  `rg-securenet-monitoring-dev-eus-001`: 90-day retention, shared-key access
  disabled, 1 GB/day cap.
- Diagnostic setting `diag-activity-log-to-law`: subscription Activity Log,
  all categories.
- Microsoft Sentinel enabled on the workspace.
- Key Vault diagnostic setting (`AuditEvent`) deployed with the workload, which
  finds the workspace through a `data` source.

| Rule | Query source | Logic | Frequency / period | Severity |
|---|---|---|---|---|
| Run Command executed (SEC-016) | `AzureActivity` | `RUNCOMMAND/ACTION` with status `Success` or `Failure` | 5 min / 5 min | High |
| Repeated Key Vault access denials (SEC-016) | `AzureDiagnostics` | `httpStatusCode_d == 403`, 5 or more per identity | 10 min / 10 min | Medium |

## Results

| # | Trigger | Event | Incident | Delay | Triage |
|---|---|---|---|---|---|
| 1 | `az vm run-command` on `vm-app` | 14:22 | #1 created 14:28 | ~7 min | Closed: expected activity, planned test for #21 |
| 2 | 6 secret reads from the operator workstation (Internet) | 14:58 | #2 alert generated 15:08 | ~10 min | Closed: expected activity, planned test for #21 |

## Test 1: run-command

```
az vm run-command invoke -g rg-securenet-dev-eus-001 \
  -n vm-app-securenet-dev-eus-001 --command-id RunShellScript \
  --scripts "@scripts/test-kv-access.sh"

Token obtained (length: 1899)
HTTP status: 404
Error: SecretNotFound / -
```

The `404` is expected: the vault was freshly deployed and the secret had not
been created. The test only needed the execution itself and a Key Vault request.

Activity Log row, as read by the rule:

| TimeGenerated | Caller | CallerIpAddress | Status | Resource |
|---|---|---|---|---|
| 14:22:05 | `<operator>` | `<operator-home-ip>` | `Success` | `vm-app-securenet-dev-eus-001` |

Sentinel created incident #1, "Run Command executed (SEC-016)", severity High,
at 14:28. Triage: the caller and IP matched the operator, and issue #21 covered
the execution. Closed as expected activity.

The same request left this Key Vault audit record (excerpt):

| Field | Value | Meaning |
|---|---|---|
| `CallerIPAddress` | `10.0.1.4` | The request came from `vm-app` over the private network |
| `privateEndpointId_s` | `.../pe-kv-securenet-dev-eus-001` | It entered through the private endpoint |
| `identity_claim_xms_mirid_s` | `.../vm-app-securenet-dev-eus-001` | Caller: the VM's managed identity |
| `httpStatusCode_d` | `404` | Secret not found |
| `ResultType` | `Success` | Reported as success despite the 404 (see finding 2) |

## Test 2: repeated Key Vault denials

Six requests for the secret from the operator workstation, outside the VNet:

```
1..6 | ForEach-Object { az keyvault secret show --vault-name kv-securenet-dev-eus-001 --name db-password }

ERROR: (Forbidden) Connection is not an approved private link and caller was ignored
because bypass is not set to 'AzureServices' and PublicNetworkAccess is set to 'Disabled'.
(× 6)
```

Key Vault audit records for the denied requests:

| TimeGenerated | CallerIPAddress | ResultSignature | identity_claim_oid_g |
|---|---|---|---|
| 14:59:00 | `<operator-home-ip>` | `Forbidden` | `<operator-object-id>` |
| … | … | … | … (one row per request) |

Sentinel generated the alert at 15:08 and linked it to incident #2,
"Repeated Key Vault access denials (SEC-016)", severity Medium. The incident
showed only an object ID. Triage resolved it to a person before closing:

```
az ad signed-in-user show --query "{name:displayName, id:id}" -o table
```

The object ID matched the operator. Closed as expected activity, planned test
for #21.

## Findings

1. **Requests rejected at the network layer are logged, with the caller's
   identity.** The vault records `ForbiddenByConnection` denials in
   `AuditEvent` together with the token's object ID, even though the request
   never reaches the data. The 403 rule therefore sees attempts from outside
   the VNet, not only from inside.
2. **`ResultType` does not reflect the HTTP result.** A `404` is logged with
   `ResultType = Success`. The rule filters on `httpStatusCode_d` instead.
3. **Columns appear only after the first matching event.** `identity_claim_upn_s`
   exists only once a user principal has accessed the vault. The query reads it
   with `column_ifexists` so the rule does not fail on a new workspace. For the
   same reason, the 403 rule could only be created after the workload was
   deployed and the vault had produced its first log.
4. **End-to-end delay was 7 to 10 minutes.** The run-command event was not
   missed despite the 5-minute rule window, but ingestion delay remains a risk
   for short windows.
5. **Incidents carry no entities.** Both incidents showed "Entities (0)"; the
   analyst had to read the caller, IP and resource from the raw events.
   Tracked as SEC-017 (entity mapping).
6. **Sentinel enabled a built-in rule on its own.** "Advanced Multistage Attack
   Detection" (Fusion) appeared after onboarding. It is managed by Microsoft,
   not by this repository, and is not drift.
7. **Classification matters for tuning.** Incident #2 was first closed as
   *False positive*. The rule fired correctly on real denials; marking it a
   false positive would later read as a noisy rule. The correction to
   *Informational, expected activity* was only saved on 2026-10-19
   ([evidence](sentinel-entity-mapping-test.md), finding 6).
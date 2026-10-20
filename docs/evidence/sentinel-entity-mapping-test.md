# Evidence: Sentinel entity mapping and late-arriving events

**Date:** 2026-10-19
**Issues:** #23 (SEC-017), SEC-020
**Objective:** Verify that incidents carry the account, IP and resource
involved, without opening the raw events. While testing, a second defect was
found and fixed: the run-command rule missed events that arrived late.

Times are in UTC. The operator's local time is UTC-5.

## Setup

Both analytics rules in [`governance/sentinel.tf`](../../governance/sentinel.tf)
map three entities. Each mapping uses a column that the rule's own query
returns:

| Rule | Account | IP | AzureResource |
|---|---|---|---|
| Run Command executed | `Caller` | `CallerIpAddress` | `_ResourceId` |
| Repeated Key Vault access denials | `Identity` | `FirstCallerIP` | `VaultId` |

The Key Vault rule cannot reuse the raw columns: its `summarize` keeps only the
grouping columns and the ones it calculates, so `CallerIPAddress` and
`_ResourceId` no longer exist after it. `FirstCallerIP` takes the first value
of the `CallerIPs` list, because an IP entity needs a single address.

## Results

| # | Test | Result |
|---|---|---|
| 1 | Entity mappings read back from Azure (`az rest`) | ✅ 3 per rule, columns as above |
| 2 | 6 denied requests to the vault from the operator workstation (18:37) | ✅ Incident #3 at 18:50 with Account and AzureResource |
| 3 | Run-command on `vm-app` (18:37) | ❌ No incident |
| 4 | Run-command on `vm-app` (19:00), repeat of test 3 | ❌ No incident |
| 5 | Run-command after the SEC-020 fix (19:43) | ✅ Incident #4 at 19:52 with Account and AzureResource |
| 6 | Incidents #1 to #4 reclassified and exported | ✅ All resolved as security testing |

## Test 1: mappings stored in Azure

The rules were read through the Azure REST API, not from the code:

```
az rest --method get --url "$base/alert-run-command-executed?api-version=2024-09-01" \
  --query "properties.entityMappings[].{tipo:entityType, columna:fieldMappings[0].columnName}" -o table

Tipo           Columna
-------------  ---------------
Account        Caller
IP             CallerIpAddress
AzureResource  _ResourceId

Tipo           Columna
-------------  -------------
Account        Identity
IP             FirstCallerIP
AzureResource  VaultId
```

## Test 2: Key Vault denials

```
1..6 | ForEach-Object { az keyvault secret list --vault-name kv-securenet-dev-eus-001 -o none }

(Forbidden) Connection is not an approved private link and caller was ignored because
bypass is not set to 'AzureServices' and PublicNetworkAccess is set to 'Disabled'.
Inner error: { "code": "ForbiddenByConnection" }
(× 6)
```

Incident #3, exported from the incident queue:

| Field | Value |
|---|---|
| Incident | Repeated Key Vault access denials (SEC-016), #3 |
| Impacted assets | Accounts: `<operator display name>`, Cloud Resources: `kv-securenet-dev-eus-001` |
| Evidence: IP | `<operator public IP>` |
| Created | 18:50 |

The incidents from SEC-016 (#1 and #2) show `Impacted assets: -` in the same
export.

## Tests 3 and 4: run-command events missed

Two run-commands succeeded on the VM and produced no incident:

```
"message": "Enable succeeded: \n[stdout]\nSEC-017 entity test\n\n[stderr]\n"
```

The events were in the workspace. Comparing when each event happened
(`TimeGenerated`) with when it arrived (`ingestion_time()`):

```kql
AzureActivity
| where TimeGenerated > ago(3h)
| where OperationNameValue =~ "MICROSOFT.COMPUTE/VIRTUALMACHINES/RUNCOMMAND/ACTION"
| extend Llegada = ingestion_time()
| extend RetrasoMin = datetime_diff('minute', Llegada, TimeGenerated)
| project TimeGenerated, Llegada, RetrasoMin, ActivityStatusValue
```

| TimeGenerated | Arrived | Delay | Status |
|---|---|---|---|
| 18:37:23 | 18:47:56 | 10 min | `Success` |
| 19:00:15 | 19:09:20 | 9 min | `Success` |

The rule ran every 5 minutes over events whose `TimeGenerated` fell in the
last 5 minutes. When an event arrived, its `TimeGenerated` was already older
than every later window, so no run ever saw it:

```
Event happened 18:37            Event arrived 18:48
Run 18:40 → window 18:35–18:40 → not arrived yet
Run 18:45 → window 18:40–18:45 → 18:37 outside the window
Run 18:50 → window 18:45–18:50 → 18:37 outside the window
```

## Test 5: fix verified (SEC-020)

The rule now selects events by arrival time and looks back 1 hour by
`TimeGenerated`:

```kql
AzureActivity
| where ingestion_time() > ago(5m)
| where OperationNameValue =~ "MICROSOFT.COMPUTE/VIRTUALMACHINES/RUNCOMMAND/ACTION"
| where ActivityStatusValue in ("Success", "Failure")
| project TimeGenerated, Caller, CallerIpAddress, ActivityStatusValue, _ResourceId
```

`query_frequency = PT5M`, `query_period = PT1H`. Each event is evaluated once,
in the run after it arrives, as long as it arrives within an hour.

Incident #4, exported from the incident queue:

| Field | Value |
|---|---|
| Incident | Run Command executed (SEC-016), #4 |
| Impacted assets | Accounts: `<operator UPN>`, Cloud Resources: `vm-app-securenet-dev-eus-001` |
| Evidence: IP | `<operator public IP>`, the same as incident #3 |
| Event / created | 19:43 / 19:52 |

The two run-commands missed earlier did not produce late incidents after the
change: they had arrived more than 5 minutes before the first run of the new
query.

## Test 6: triage

All four incidents were closed with classification *Informational, expected
activity* (exported as `Benign Positive`) and determination *Security
testing*, each with a comment referencing its ticket.

| Incident | Status | Classification | Determination |
|---|---|---|---|
| #1 Run Command (SEC-016) | Resolved | Benign Positive | Security testing |
| #2 Key Vault denials (SEC-016) | Resolved | Benign Positive | Security testing |
| #3 Key Vault denials (SEC-017) | Resolved | Benign Positive | Security testing |
| #4 Run Command (SEC-020) | Resolved | Benign Positive | Security testing |

## Findings

1. **Entity mapping works, and the IP is not an impacted asset.** Incidents
   list the account and the resource under *Impacted assets*. The IP appears
   only in the incident's evidence. Both incidents show the same IP, which
   links them to one origin.
2. **The account is shown differently by each rule.** The run-command rule
   maps `Caller`, which already holds the UPN. The Key Vault log holds the
   object ID, and Sentinel resolved it to the user's display name through
   Entra ID.
3. **The SEC-016 run-command test passed by chance.** That day the event
   arrived in under 5 minutes. With 9 to 10 minutes of ingestion delay, a
   5-minute window by `TimeGenerated` misses every event. SEC-016 finding 4
   had flagged the risk; this test confirmed it.
4. **Measure ingestion delay before choosing a rule window.**
   `ingestion_time() - TimeGenerated` showed the cause in one query. Repeating
   the run-command a second time added no information.
5. **The Key Vault rule has the same exposure.** It still counts denials by
   `TimeGenerated` over 10 minutes and fired in this test. Changing it alters
   what "5 denials in 10 minutes" means, so it is tracked separately.
6. **A classification is saved only when the export shows it.** The SEC-016
   evidence stated that incident #2 had been corrected to expected activity.
   The export still showed `False alert` for #2 and `Not set` for #1 until
   both were corrected in this test.
7. **The SEC-017 apply ran from the feature branch, before merge.** The only
   local difference was a trailing space. After merge, `terraform plan` from
   `main` reported `No changes`, which confirmed that Azure matches the
   reviewed code. Applies run from `main` with a saved plan (`-out`).
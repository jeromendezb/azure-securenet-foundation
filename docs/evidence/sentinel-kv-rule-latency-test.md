# Evidence: Key Vault denial rule and ingestion delay

**Date:** 2026-10-20
**Issues:** #36 (fix, PR #37), #38 (alert grouping, open)
**Objective:** Measure how late Key Vault audit events arrive, decide whether
the denial rule can miss a burst because of it, and verify the fix.

Times are in UTC. The operator's local time is UTC-5.

## Results

| # | Test | Result |
|---|---|---|
| 1 | Ingestion delay of Key Vault `AuditEvent` (6 denied requests) | 3 to 5 minutes |
| 2 | Old rule (10-minute window, every 10 minutes) on that burst | Incident #5. Fired, but it could only fire in about half of the possible run times |
| 3 | New rule (25-minute window, every 5 minutes) on a new burst | Incidents #6 and #7 from two consecutive runs. The burst is visible in more than one run |
| 4 | Alert grouping by account, applied twice | ❌ Not persisted by Azure. Removed from the code (#38) |

## Test 1: ingestion delay

Six requests to the vault from the operator workstation, denied with
`ForbiddenByConnection`. Delay between the event and its arrival in the
workspace:

```kql
AzureDiagnostics
| where TimeGenerated > ago(1h)
| where ResourceProvider == "MICROSOFT.KEYVAULT" and Category == "AuditEvent"
| where httpStatusCode_d == 403
| extend Llegada = ingestion_time()
| extend RetrasoMin = datetime_diff('minute', Llegada, TimeGenerated)
| project TimeGenerated, Llegada, RetrasoMin
| order by TimeGenerated asc
```

| TimeGenerated | Arrived | Delay |
|---|---|---|
| 16:16:28 | 16:20:13 | 4 min |
| 16:16:30 | 16:19:39 | 3 min |
| 16:16:32 | 16:21:08 | 5 min |
| 16:16:34 | 16:20:04 | 4 min |
| 16:16:36 | 16:20:54 | 4 min |
| 16:16:37 | 16:19:59 | 3 min |

One more 403 at 16:08:10, eight minutes before the test, was not identified.

## Test 2: why the old rule could miss the burst

The old rule ran every 10 minutes and counted denials whose `TimeGenerated`
fell in the last 10 minutes. It fires only when one run sees 5 or more:

```
Run before 16:20:54            → fewer than 5 had arrived          ✗
Run between 16:20:54 and 16:26:30 → 5 or 6 visible                 ✓
Run after 16:26:30             → the first denials left the window ✗
```

The firing interval is about 5.5 minutes out of every 10. The rule fired on
this burst (incident #5, created 16:30), but whether it fires depends on
where the run falls, not on the activity.

## Test 3: overlapping windows (PR #37)

The window must cover the detection window, the delay and the time between
runs:

```
query_period >= detection window + delay budget + frequency
             =        10         +      10      +     5     = 25 minutes
```

The delay budget is 10 minutes, twice the measured maximum, because there is
one measurement. New settings: `query_frequency = PT5M`,
`query_period = PT25M`.

The run time was not recorded for this test. The incident export shows the
same burst detected by two consecutive runs:

| Incident | Alert window ends | Created |
|---|---|---|
| #6 | 17:04:29 | 17:09:40 |
| #7 | 17:09:29 | 17:14:51 |

## Test 4: alert grouping not persisted

Overlapping runs see the same burst more than once, so the rule was given an
incident grouping block: group alerts by `Account` for 1 hour. The plan
showed the change and the apply succeeded. Read back from Azure:

```
az rest --method get --url "$base/alert-kv-repeated-denials?api-version=2024-09-01" \
  --query "properties.incidentConfiguration.groupingConfiguration" -o json

{
  "enabled": false,
  "groupByEntities": [],
  "lookbackDuration": "PT5M",
  "matchingMethod": "AllEntities",
  ...
}
```

A second apply gave the same result. With the block in the code, every plan
showed `1 to change`, a perpetual difference that would hide real drift. The
block was removed; the plan then reported `No changes`.

## Findings

1. **A short delay is enough to break a short window.** Key Vault events
   arrived 3 to 5 minutes late, half the delay of `AzureActivity`, and the old
   rule could still miss a burst about half the time.
2. **The window can be sized from three numbers.** Detection window, delay
   budget and run frequency. Measuring the delay first is what makes the
   number defensible.
3. **The rule is now less strict.** It counts 5 or more denials in 25
   minutes, not in 10. The threshold had never been baselined against normal
   traffic, so this was accepted.
4. **Overlap creates duplicate incidents.** One burst produced incidents #6
   and #7. Duplicates were preferred over suppression, which would hide a
   second identity denied within the suppression period.
5. **An accepted setting is not a persisted setting.** The grouping was
   accepted on apply and discarded by Azure. Only reading the rule back with
   `az rest` showed it. Microsoft documents that rules excluded from Defender
   correlation group alerts by the rule's own configuration, so the cause is
   still unknown (#38).
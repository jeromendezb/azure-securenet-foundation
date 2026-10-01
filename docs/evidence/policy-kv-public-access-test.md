# Evidence: Azure Policy denies public Key Vaults

**Date:** 2026-10-01
**Ticket:** SEC-015
**Objective:** Verify that no Key Vault with public network access can be
created anywhere in the subscription, while compliant vaults are still allowed.

## Setup

- Built-in policy *Azure Key Vault should disable public network access*
  (`405c5871-3e91-4644-8a63-58e19d68ff5b`, version 1.1.0).
- Assignment `kv-disable-public-access` at subscription scope, managed from
  [`governance/`](../../governance/) ([ADR-003](../adr/adr-003-subscription-guardrails.md)).
- Rollout: applied with `Audit`, then changed to `Deny` (`0 added, 1 changed,
  0 destroyed`). No Key Vaults existed in the subscription, so there was nothing
  to remediate before switching.
- Tests ran with Azure CLI as the operator, who holds the `Owner` role, in a
  temporary resource group (`rg-policytest`) outside this project.

## Results

| # | Request | Expected | Result |
|---|---|---|---|
| 1 | Create a vault with `--public-network-access Enabled` | Denied | ✅ `RequestDisallowedByPolicy` |
| 2 | Create a vault with `--public-network-access Disabled` | Allowed | ✅ Created |

## Test 1: public vault denied

```
(RequestDisallowedByPolicy) Resource 'kv-poltest-jero01' was disallowed by policy.
Policy identifiers: '[{"policyAssignment":{"name":"Key Vaults must disable public
network access (SEC-015)", ...},"policyDefinition":{"name":"Azure Key Vault should
disable public network access", ...,"version":"1.1.0"}}]'.
```

The error's `evaluationDetails` shows how the decision was made:

| Expression | Value in the request | Condition | Result |
|---|---|---|---|
| `type` | `Microsoft.KeyVault/vaults` | equals `Microsoft.KeyVault/vaults` | True |
| `createMode` | (not set) | equals `recover` | False |
| `requestContext().apiVersion` | `2026-02-01` | ≥ `2021-06-01-preview` | True |
| `publicNetworkAccess` | `Enabled` | not equals `Disabled` | True |

The request was denied even though the caller is `Owner` of the subscription:
the policy evaluates the resource's configuration, not the caller's permissions.

## Test 2: compliant vault allowed

```
Name               PublicAccess
-----------------  --------------
kv-poltest-jero02  Disabled
```

The test vault was deleted and purged, and the temporary resource group deleted.

## Findings

1. **Policy is enforced against Owners.** RBAC cannot express "nobody may do
   this"; Policy can.
2. **The definition does not evaluate vault recovery.** The `createMode`
   condition shows that requests restoring a soft-deleted vault
   (`createMode = recover`) are outside this policy's check. A vault deleted
   while public could be recovered as public.
3. **The assignment took effect immediately in this test**, although Microsoft
   documents that new or changed assignments can take up to about 30 minutes.
   A test run too early could falsely look like a failed control.
4. **`2>&1` was required to capture the evidence.** Without it, PowerShell's
   `Tee-Object` saves only standard output, and the denial message, the evidence
   itself, would have been lost.
# Evidence: NSG on the private endpoint subnet

**Date:** 2026-09-30
**Issue:** #13
**Objective:** Verify that only `snet-app` and `snet-mgmt` can reach the Key
Vault private endpoint, and that any other subnet in the VNet is blocked.

## Setup

- `nsg-pe-securenet-dev-eus-001` associated with `snet-pe`:

  | Rule | Priority | Access | Source | Port |
  |---|---|---|---|---|
  | `allow-https-from-app` | 100 | Allow | `snet-app` | TCP 443 |
  | `allow-https-from-mgmt` | 110 | Allow | `snet-mgmt` | TCP 443 |
  | `deny-all-from-vnet` | 4000 | Deny | `VirtualNetwork` | Any |

  The explicit deny is required: without it, the default rule
  `AllowVnetInBound` (65000) would let every subnet in the VNet through.
- `private_endpoint_network_policies = "NetworkSecurityGroupEnabled"` on
  `snet-pe`. With the default (`Disabled`), traffic to a private endpoint
  ignores NSG rules entirely, so the NSG alone would have had no effect.
- Test script: [`test-kv-network.sh`](../../scripts/test-kv-network.sh), run
  through `az vm run-command`. It sends an **unauthenticated** request, so it
  measures only the network path: `401` means the request reached the vault;
  `000` after the 10-second timeout means the network dropped it.

## Results

| # | Phase | Source | Resolves to | Result | Time | Meaning |
|---|---|---|---|---|---|---|
| 1 | A: `mgmt` rule removed | `vm-app` | `10.0.4.4` | ✅ 401 | 0.08 s | Allowed subnet reaches the vault |
| 2 | A: `mgmt` rule removed | `vm-mgmt` | `10.0.4.4` | ✅ 000 | 10.0 s | Non-allowed subnet: packets silently dropped |
| 3 | B: full rule set | `vm-app` | `10.0.4.4` | ✅ 401 | 0.05 s | Allowed |
| 4 | B: full rule set | `vm-mgmt` | `10.0.4.4` | ✅ 401 | 0.05 s | Allowed; the ADR-002 secret-write path still works |

After phase B, `terraform plan` reported:

```
No changes. Your infrastructure matches the configuration.
```

## Test 2: blocked subnet (phase A)

```
Resolves to: 10.0.4.4
HTTP status: 000  Time: 10.002399s
```

DNS resolution is correct, so the failure is purely at the network layer.
The NSG drops the packets without answering, which is why the client waits
until the timeout instead of receiving an error. A 403 would have meant the
request reached the vault and was rejected there.

## Test 4: allowed subnet (phase B)

```
Resolves to: 10.0.4.4
HTTP status: 401  Time: 0.050963s
```

## Findings

1. **An NSG on a private endpoint subnet does nothing by default.**
   `private_endpoint_network_policies` must be enabled on the subnet;
   otherwise the control exists on paper only. Checkov flags the missing NSG
   (`CKV2_AZURE_31`) but does not check this setting.
2. **Race condition on first deploy.** The first `apply` failed with
   `ReferencedResourceNotProvisioned`: Terraform created the private endpoint
   while the NSG association was still updating `snet-pe`. The failed endpoint
   was left in Azure in `Failed` state and outside Terraform state, so the
   retry failed with "resource already exists". The orphan was deleted, and an
   explicit `depends_on` on the NSG association was added. Two later deploys
   from an empty environment completed without the error.
3. **Access control must cover every flow, not only the main one.** Allowing
   only `snet-app` would have broken the operator workflow in ADR-002, which
   writes secrets from `vm-mgmt`.
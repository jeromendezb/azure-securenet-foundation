# Evidence: Key Vault private endpoint and private DNS

**Date:** 2026-09-29
**Ticket:** SEC-014 (issue #8)
**Objective:** Verify that the Key Vault is no longer reachable from the
Internet, that `vm-app` still reads its secret through the private endpoint,
and show what happens when the private DNS zone is not linked to the VNet.

## Setup

- `kv-securenet-dev-eus-001` with `public_network_access_enabled = false` and
  `network_acls { default_action = "Deny", bypass = "None" }`.
- Private endpoint `pe-kv-securenet-dev-eus-001` in `snet-pe` (`10.0.4.0/26`).
- Private DNS zone `privatelink.vaultcore.azure.net`, with the A record
  registered by the private endpoint's DNS zone group.
- The link between the zone and the VNet was **left out on purpose** for the
  first round of tests, then added.
- Tests on `vm-app` ran through `az vm run-command` using
  [`test-kv-access.sh`](../../scripts/test-kv-access.sh), which authenticates
  with the VM's managed identity.

## Results

| # | Test | Without VNet link | With VNet link |
|---|---|---|---|
| 1 | Private DNS record exists | ✅ `kv-securenet-dev-eus-001 → 10.0.4.4` | — |
| 2 | Name resolution from `vm-app` | ❌ Public IPs | ✅ `10.0.4.4` |
| 3 | `vm-app` reads the secret | ❌ 403 `ForbiddenByConnection` | ✅ 404 `SecretNotFound` (secret not created yet), then 200 |
| 4 | Operator reads from the Internet | ✅ 403 `ForbiddenByConnection` | — |

## Test 1: the private endpoint registered its DNS record

```
Name                      Ip
------------------------  --------
kv-securenet-dev-eus-001  10.0.4.4
```

The record exists in the zone, so the private endpoint side is correct.

## Test 2: name resolution from `vm-app`

**Without the VNet link:**

```
kv-securenet-dev-eus-001.vault.azure.net  canonical name = kv-securenet-dev-eus-001.privatelink.vaultcore.azure.net.
kv-securenet-dev-eus-001.privatelink.vaultcore.azure.net  canonical name = data-prod-eus.vaultcore.azure.net.
...
Address: 40.71.10.202
Address: 20.42.64.44
Address: 20.42.73.8
```

The name goes through the `privatelink` alias, but public DNS answers it,
because the VNet does not know the private zone exists. The VM resolves the
vault's public IPs even though the private endpoint and its DNS record exist.

**With the VNet link:**

```
kv-securenet-dev-eus-001.vault.azure.net  canonical name = kv-securenet-dev-eus-001.privatelink.vaultcore.azure.net.
Name:   kv-securenet-dev-eus-001.privatelink.vaultcore.azure.net
Address: 10.0.4.4
```

## Test 3: `vm-app` reads the secret

**Without the VNet link:**

```
Token obtained (length: 1903)
HTTP status: 403
Error: Forbidden / ForbiddenByConnection
```

The request left the VNet towards a public IP and was rejected at the network
layer, before identity or the secret were evaluated. That is why the result is
403 even though the secret did not exist yet.

**With the VNet link, before the secret was created:**

```
Token obtained (length: 1903)
HTTP status: 404
Error: SecretNotFound / -
```

The network path and the RBAC check both passed. The only thing missing was
the secret itself.

**With the VNet link, after the secret was created from `vm-mgmt`:**

```
Token obtained (length: 1903)
HTTP status: 200
Secret read. Value length: 32
```

The secret was written from `vm-mgmt` inside the VNet, following
[ADR-002](../adr/adr-002-keyvault-secret-write-access.md): Bastion session,
`az login --use-device-code` with the operator's identity, value generated in
the shell with `--output none`, then `az logout`.

## Test 4: operator request from the Internet

```
(Forbidden) Connection is not an approved private link and caller was ignored
because bypass is not set to 'AzureServices' and PublicNetworkAccess is set to
'Disabled'.
Inner error: { "code": "ForbiddenByConnection" }
```

The operator has the `Key Vault Secrets Officer` role, but the request is
rejected at the network layer. A valid identity is no longer enough from
outside the VNet.

## Findings

1. **A private endpoint without the VNet link is bypassed without any
   warning.** Every resource shows as healthy in the portal, yet clients
   resolve the public IP. The first diagnostic step for a private endpoint is
   name resolution from inside the VNet.
2. **The failure mode is fail-closed.** With public access disabled, the
   misconfiguration broke availability (403), not security. If public access
   had still been enabled, the same mistake would have silently sent traffic
   over the public endpoint.
3. **Two different 403s mean two different layers.** `ForbiddenByRbac`
   (identity: authenticated but not authorized) and `ForbiddenByConnection`
   (network: the request did not arrive through an approved path).
4. **Perpetual diff unrelated to this change.** After apply, `terraform plan`
   keeps proposing the same in-place updates on both VMs
   (`vm_agent_platform_updates_enabled`) and on the diagnostic setting
   (`metric "AllMetrics"`). Tracked separately.
5. **`vm-mgmt` booted with 48 pending security updates** despite using the
   `latest` image. Patch management is not covered by this lab.
# Evidence: Key Vault access with Managed Identity

**Date:** 2026-09-25
**Objective:** Verify that only the application VM can read the database
secret, and that authenticating is not enough to access it.

## Setup

- Key Vault `kv-securenet-dev-eus-001` in RBAC authorization mode.
- Secret `db-password` created by the operator with Azure CLI. The value was
  generated in the shell, never typed, never written to Terraform state, and
  never printed (`--output none`).
- `vm-app`: system-assigned managed identity with **Key Vault Secrets User**,
  scoped to this vault only.
- `vm-mgmt`: system-assigned managed identity with **no role** on the vault.
  It exists as a control identity for the negative test.
- Both VMs obtain tokens from the Instance Metadata Service
  (`169.254.169.254`). No credential is stored on either VM.

## Results

| # | Caller | Token | Expected | Result |
|---|---|---|---|---|
| 1 | `vm-mgmt` | None | 401 | ✅ 401 `Unauthorized` |
| 2 | `vm-mgmt` | Valid, no role on the vault | 403 | ✅ 403 `ForbiddenByRbac` |
| 3 | `vm-app` | Valid, `Key Vault Secrets User` | 200 | ✅ Secret read |

## Test 1: request without a token (401)

This result was not planned. The token variable was empty because it had
been set in a different shell session. It is kept because it shows the
authentication layer on its own: without a token, Key Vault does not
evaluate permissions at all.

```
{"error":{"code":"Unauthorized","message":"AKV10000: Request is missing a Bearer, PoP, or MTLS_POP token."}}
```

## Test 2: valid identity without a role (403)

`vm-mgmt` obtained a valid token (1900 characters) and requested the secret.
Output formatted for readability; subscription and tenant IDs redacted:

```
Code: Forbidden
Inner error: ForbiddenByRbac
Caller: appid=1226e8e5-d0f6-47ed-a3ad-423bc705f27e;oid=92e90046-b72b-46c8-9e09-91dea5ec9dd1;iss=https://sts.windows.net/<tenant-id>/
Action: 'Microsoft.KeyVault/vaults/secrets/getSecret/action'
Resource: '/subscriptions/<subscription-id>/resourcegroups/rg-securenet-dev-eus-001/providers/microsoft.keyvault/vaults/kv-securenet-dev-eus-001/secrets/db-password'
Assignment: (not found)
```

The caller `oid` was correlated with the VM's managed identity:

```
> az vm show -g rg-securenet-dev-eus-001 -n vm-mgmt-securenet-dev-eus-001 --query identity.principalId -o tsv
92e90046-b72b-46c8-9e09-91dea5ec9dd1
```

The denied caller is `vm-mgmt`, and the denial reason is the absence of a
role assignment, not a network or firewall rule.

## Test 3: application identity with the correct role (200)

```
id: https://kv-securenet-dev-eus-001.vault.azure.net/secrets/db-password/d50e355471f84faca0584e4718676386
value length: 36
```

The secret value is intentionally not printed. Its length (36, a GUID) proves
it was read without exposing it in the evidence.

## Secret inventory (operator view)

```
Name         Enabled
-----------  -------
db-password  True
```

## Interpretation

- **Authentication and authorization are separate layers.** Test 1 fails
  authentication; test 2 passes authentication and fails authorization.
- **Least privilege works as designed.** The role is scoped to one vault and
  granted to one identity. A second identity in the same network and resource
  group is denied.
- **No secret lives on the VMs.** The application VM reads the secret at
  runtime using its own identity.

## Limitations

- **No data-plane logs.** Key Vault diagnostic settings were not enabled, so
  secret reads were not recorded. It is not possible to show *who read the
  secret and when*. This is the next step for this project.
- **Public network access to the vault is enabled.** Access still requires a
  valid token and role. Production would use a private endpoint and disable
  public access.
- **Purge protection disabled.** Lab-only simplification.
- **Deployed with the operator's user account (Owner)**, not a least-privilege
  pipeline identity. Planned for Project 3 with OIDC.
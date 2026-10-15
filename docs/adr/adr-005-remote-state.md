# ADR-005: Terraform state in Azure Storage, protected by identity

- **Status:** Accepted
- **Date:** 2026-10-15
- **Deciders:** Jero Méndez
- **Supersedes:** —
- **Superseded by:** —

## Context

Security finding SEC-018 reports that both Terraform roots (the workload and
`governance/`) keep their state in local files on the operator's workstation.

The state is Terraform's record of which real resource matches each block of
code. Keeping it locally has four problems:

1. **Loss.** If the workstation is lost or the file is deleted, Terraform no
   longer knows what it created. The resources keep running and billing, but
   cannot be changed or destroyed with Terraform.
2. **Sensitive data on disk.** The state contains values such as the Log
   Analytics shared keys, on an unencrypted local disk.
3. **No locking.** Two `apply` runs at the same time read the same state and
   the last write wins. Resources created by the other run are left outside
   the state, as happened with the orphaned private endpoint during SEC-014.
4. **No automation.** The CI pipeline cannot run `terraform plan`, because it
   has no access to the state.

## Decision

### 1. Remote backend in Azure Storage

Both roots use the `azurerm` backend, each with its own state file in one
container:

| Root | State file |
|---|---|
| Workload | `workload.tfstate` |
| `governance/` | `governance.tfstate` |

The backend locks the state file (blob lease) during every operation that
writes it, so a second run waits instead of overwriting.

### 2. The storage account is created by a script, outside Terraform

Terraform reads the backend configuration during `terraform init`, before it
can create anything. The storage account must therefore exist before
Terraform runs, so it cannot be created by the root whose state it stores.

A versioned Azure CLI script (`scripts/bootstrap-state.ps1`) creates it once,
in its own resource group. The script is idempotent: running it again does not
change an existing account.

### 3. Protection by identity, not by network

| Control | Setting |
|---|---|
| Shared keys disabled | Only Entra ID can access the data; no account key exists to leak |
| Backend authenticates with Entra ID | `use_azuread_auth = true` |
| Least privilege | `Storage Blob Data Contributor` on this account only, for the operator (and later the CI identity) |
| No anonymous access | Public blob access disabled |
| Recovery | Blob versioning and 7-day soft delete for blobs and containers |
| Encryption in transit | HTTPS only, minimum TLS 1.2 |
| Encryption at rest | Azure Storage default (always on) |

The public endpoint stays open, protected by identity.

## Alternatives considered

### 1. Private endpoint, public access disabled

Deferred as the production target. Terraform runs from the operator's
workstation and, later, from GitHub-hosted runners, both on the Internet.
With public access disabled, neither could read the state. Making it work
needs a VPN or a self-hosted runner inside a permanent VNet, which adds cost
and operational work this lab does not justify. Same reasoning as
[ADR-002](adr-002-keyvault-secret-write-access.md).

### 2. Storage firewall allowing the operator's IP

Rejected. GitHub-hosted runners use changing IP addresses, and the operator's
home IP changes without notice. It would break unpredictably and still leave a
public network rule as the main control.

### 3. Create the storage account with Terraform

Rejected for this lab. Either it needs its own local state (the problem this
ADR removes) or a two-step migration of its own state into itself, which is
harder to explain and to recover when it fails.

### 4. Terraform Cloud or another hosted backend

Rejected. It adds an external service and account outside Azure. The goal is
to keep the state inside the same tenant and governed by the same identities.

## Consequences

### Positive

- State survives the loss of the workstation, with version history.
- No sensitive values on the local disk.
- Concurrent runs are blocked by the lock instead of corrupting the state.
- The CI pipeline can read the state, which unblocks `terraform plan` with OIDC.

### Negative

- **The state is reachable from the Internet** for any identity with the role.
  Mitigation: shared keys disabled, role scoped to this account, sign-in
  protected by Entra ID. Accepted for the lab; private endpoint is the
  production target.
- **The storage account is not managed by Terraform.** Changes to it must go
  through the script. Mitigation: the script is versioned and idempotent.
- **One more always-on resource.** Mitigation: a few kilobytes of state cost
  cents per month.
- **Losing the role means losing Terraform.** If the operator's role
  assignment is removed, every `plan` fails with 403. This is intended.

## Future work

- Grant `Storage Blob Data Contributor` to the CI identity when OIDC is added.
- Private endpoint and self-hosted runner for production.
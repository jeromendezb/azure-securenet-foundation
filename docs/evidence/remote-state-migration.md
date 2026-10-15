# Evidence: Terraform state migrated to Azure Storage

**Date:** 2026-10-15
**Issue:** #25 (SEC-018)
**Objective:** Move the state of both Terraform roots from the operator's
workstation to Azure Storage, without recreating any resource.

## Setup

- Storage account `stsecurenettfstate001` in `rg-securenet-tfstate-dev-eus-001`,
  created by [`bootstrap-state.ps1`](../../scripts/bootstrap-state.ps1)
  ([ADR-005](../adr/adr-005-remote-state.md)):
  shared keys disabled, no anonymous blob access, HTTPS only with TLS 1.2,
  blob versioning, 7-day soft delete for blobs and containers.
- `Storage Blob Data Contributor` for the operator, scoped to the account.
- Container `tfstate`.
- Backend `azurerm` in both roots with `use_azuread_auth = true`.

## Results

| # | Step | Result |
|---|---|---|
| 1 | Bootstrap script | ✅ All 5 steps completed |
| 2 | Workload root: `init -migrate-state` | ✅ Backend configured. No prompt to copy: the lab was destroyed, so the local state had no resources |
| 3 | Workload root: `plan` | ✅ `25 to add` (nothing deployed), state read from Azure |
| 4 | `governance/`: local state backed up outside the repository | ✅ |
| 5 | `governance/`: `init -migrate-state` | ✅ State copied after confirmation, under lock |
| 6 | `governance/`: `plan` | ✅ `No changes` |
| 7 | Both state files in the container | ✅ `governance.tfstate`, `workload.tfstate` |
| 8 | Local state files deleted, `governance/` `plan` again | ✅ `No changes` |

## Test 5: migration of a state with live resources

```
Initializing the backend...
Acquiring state lock. This may take a few moments...
Do you want to copy existing state to the new backend?
  Pre-existing state was found while migrating the previous "local" backend to the
  newly configured "azurerm" backend. No existing state was found in the newly
  configured "azurerm" backend. Do you want to copy this state to the new "azurerm"
  backend? Enter "yes" to copy and "no" to start with an empty state.

  Enter a value: yes

Releasing state lock. This may take a few moments...

Successfully configured the backend "azurerm"! Terraform will automatically
use this backend unless the backend configuration changes.
```

## Tests 6 and 8: nothing to recreate

```
No changes. Your infrastructure matches the configuration.
Releasing state lock. This may take a few moments...
```

Terraform, reading the state from Azure, recognized the policy assignment,
the workspace, the Activity Log diagnostic setting, Sentinel and both
analytics rules as existing. Test 8 repeated the plan after the local files
were deleted, so the result cannot come from a leftover local copy.

## Test 7: state files in the container

```
az storage blob list --account-name stsecurenettfstate001 --container-name tfstate \
  --auth-mode login --query "[].name" -o tsv

governance.tfstate
workload.tfstate
```

## Findings

1. **A backend block that is not on disk does nothing, silently.** The first
   `init -migrate-state` of the workload root printed no
   `Successfully configured the backend` line: the edited `providers.tf` had
   not been saved. A `plan` still succeeded, using the local state. The
   migration was only confirmed by listing the container in Azure.
2. **An empty state is not migrated.** With no resources in the local state,
   `init` skips the copy prompt, and the state file only appears in the
   container after the first operation that takes the lock.
3. **Locking needs no configuration.** The `azurerm` backend acquired and
   released the lock on its own during `init` and every `plan`.
4. **Start with the root that can lose least.** The workload root (empty) was
   migrated first; `governance/` (live resources) only after the method was
   proven, with a backup taken beforehand.
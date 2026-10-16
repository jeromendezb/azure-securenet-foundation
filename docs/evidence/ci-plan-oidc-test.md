# Evidence: CI plan with OIDC

**Date:** 2026-10-16
**Issue:** #27 (SEC-019)
**Objective:** Run `terraform plan` for both roots on every pull request,
signed in to Azure with OIDC, with a read-only identity, and without exposing
anything in the public log.

## Setup

Defined in [`governance/ci-identity.tf`](../../governance/ci-identity.tf)
([ADR-006](../adr/adr-006-ci-plan-with-oidc.md)):

- User-assigned managed identity `id-securenet-ci-dev-eus-001` in
  `rg-securenet-cicd-dev-eus-001`.
- Federated credential: issuer `https://token.actions.githubusercontent.com`,
  audience `api://AzureADTokenExchange`, subject for this repository's pull
  requests only.
- `Reader` on the subscription; `Storage Blob Data Contributor` on the state
  storage account only.

In GitHub: `AZURE_CLIENT_ID`, `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID` as
secrets (masked in logs), `SSH_PUBLIC_KEY` as a variable. No Azure secret.

## Results

Each row is one run of the `Terraform plan` job on the pull request. Every
failure was diagnosed before changing anything.

| # | Result | Error | Cause | Fix |
|---|---|---|---|---|
| 1 | ❌ | `AADSTS700016` Application not found in the directory | Wrong value in the client ID or tenant ID secret | Values read again from the identity with `az identity show` and re-entered |
| 2 | ❌ | `AADSTS700213` No matching federated identity record | GitHub presents an immutable subject with owner and repository IDs; the credential expected names only | Subject updated to the presented value |
| 3 | ❌ | Same as #2 | The change was saved but never applied. `az identity federated-credential list` showed the old subject in Azure | `apply`, then verified in Azure |
| 4 | ❌ | `no file exists at "/home/runner/.ssh/securenet_lab.pub"` | The workload reads the SSH public key from the operator's disk; the runner is a clean machine | Key written from the `SSH_PUBLIC_KEY` variable before planning |
| 5 | ✅ | — | Both roots planned. `governance/` reported `2 to change` on the Sentinel rules, while the same code reported `No changes` on the workstation | See test 6 |
| 6 | ✅ | — | Both roots planned, `governance/`: `No changes` | — |

## Test 2: Entra ID rejects a subject that does not match exactly

```
AADSTS700213: No matching federated identity record found for presented
assertion subject 'repo:jeromendezb@294006608/azure-securenet-foundation@1374980134:pull_request'.
```

The trust rule held: a token from the right repository, but with a subject
that did not match character for character, received no Azure access.

## Test 5: a difference only CI could see

```
# azurerm_sentinel_alert_rule_scheduled.kv_repeated_denials will be updated in-place
# azurerm_sentinel_alert_rule_scheduled.vm_run_command will be updated in-place
Plan: 0 to add, 2 to change, 0 to destroy.
```

Hypothesis: line endings. Git on Windows (`core.autocrlf = true`) checks files
out with CRLF. The rules were applied from Windows, so Azure stored the
multi-line KQL queries with CRLF; the Linux runner reads the same files with
LF. The two Sentinel rules are the only resources with multi-line values.

Verification on the workstation:

```
git config core.autocrlf                                   → true
git ls-files --eol governance/sentinel.tf                  → i/lf  w/crlf  attr/text eol=lf
```

Fix: a `.gitattributes` that forces LF for `.tf`, `.hcl`, `.yml`, `.sh` and
`.kql` files, the working copies re-checked out, then the workstation plan
reproduced `2 to change`. After `apply`, both the workstation and CI report
`No changes`.

## Test 6: the public log

```
No changes. Your infrastructure matches the configuration.
```

```
  # azurerm_key_vault.main will be created
  # azurerm_linux_virtual_machine.app will be created
  ...
  # azurerm_virtual_network.main will be created
Plan: 25 to add, 0 to change, 0 to destroy.
```

The log contains resource addresses and the summary only: no attribute values,
no resource IDs, no subscription ID, no e-mail address. Where an error message
included the client or tenant ID, GitHub replaced it with `***`.

## Findings

1. **OIDC removes the secret, not the configuration work.** Four failures
   before the first green run, none of them a security weakness: two wrong
   values, one change not applied, one missing file.
2. **GitHub's OIDC subject includes immutable IDs.** Matching on names alone
   fails; the IDs also prevent a re-created repository with the same name from
   matching.
3. **Verify in Azure, not in the file.** Test 3 failed because the change only
   existed in the editor. One `az` query showed it.
4. **A plan in CI catches what a workstation plan cannot.** The CRLF drift was
   invisible from Windows. An `apply` from Linux or macOS would have changed
   both rules without anyone knowing why.
5. **`Reader` plus the state role was enough** for both roots; no extra
   permission was needed.
6. **The provider lock file needs every platform.** It only had Windows
   hashes, so CI rewrote it on every run. Fixed with
   `terraform providers lock -platform=windows_amd64 -platform=linux_amd64`.
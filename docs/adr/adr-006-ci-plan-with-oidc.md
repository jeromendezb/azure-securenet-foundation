# ADR-006: CI runs terraform plan with OIDC and a read-only managed identity

- **Status:** Accepted
- **Date:** 2026-10-16
- **Deciders:** Jero Méndez
- **Supersedes:** —
- **Superseded by:** —

## Context

Security finding SEC-019 (issue #27) reports that the CI pipeline only checks
syntax (`fmt`, `validate`, Checkov). It has no access to Azure, so
`terraform plan` runs only on the operator's workstation, when the operator
remembers to run it, against whatever is in the local folder.

A pull request can therefore be merged without anyone seeing what it does in
Azure. A one-line change can force a resource to be replaced: renaming a Key
Vault destroys it and creates a new one, with its secrets. The code diff looks
harmless; only the plan shows `1 to destroy`.

To run `plan`, the pipeline needs an identity in Azure. The usual way is a
service principal with a client secret stored in GitHub. That secret can leak
through a log, a compromised GitHub account or a malicious workflow, stays
valid for months, and has to be rotated.

The remote state from [ADR-005](adr-005-remote-state.md) is a prerequisite:
the pipeline can now read the state from Azure Storage.

## Decision

### 1. OIDC federation, no stored secret

The pipeline authenticates with OpenID Connect. On every run, GitHub issues a
short-lived token signed by GitHub that states which repository and which
event the run belongs to. Entra ID checks the signature against a federated
credential and returns an Azure access token valid for minutes. Nothing is
stored in GitHub except identifiers (client ID, tenant ID, subscription ID).
None of them is a credential, but they are stored as GitHub secrets so that
GitHub masks them in the public logs.

### 2. A user-assigned managed identity

The CI identity is a user-assigned managed identity, defined in `governance/`
with its federated credential and role assignments. A managed identity cannot
hold a client secret, so a "temporary" secret can never be added later.

### 3. Trusted only for this repository's pull requests

The federated credential accepts exactly one subject:

```
repo:jeromendezb@294006608/azure-securenet-foundation@1374980134:pull_request
```

The subject includes GitHub's immutable owner and repository IDs. A
repository deleted and re-created with the same name gets a new ID and does
not match. Runs from other repositories or from pushes to any branch are
rejected by Entra ID. Pull requests from forks never receive a token: GitHub
does not grant them permission to request one.

### 4. Read-only, plus the state lock

| Role | Scope | Why |
|---|---|---|
| `Reader` | Subscription | Read every resource to compare it with the code. Cannot change anything |
| `Storage Blob Data Contributor` | State storage account only | `plan` takes a lock on the state file, and taking the lock is a write |

### 5. Plan only, apply stays manual

The pipeline runs `terraform plan` for both roots on every pull request. It
never runs `apply`. The operator applies after merge, as today.

### 6. Only a summary of the plan goes to the log

The repository is public, so its Actions logs are public too. A full plan
prints attribute values such as resource IDs, which contain the subscription
ID that the evidence files redact. The pipeline prints only the list of
resource actions and the summary line, for example:

```
# azurerm_key_vault.main must be replaced
Plan: 1 to add, 0 to change, 1 to destroy.
```

That is what a reviewer needs to stop a destructive change.

### 7. The SSH public key comes from a repository variable

The workload reads the SSH public key from a file on the machine that runs
Terraform. The runner is a clean machine, so the job writes the key from the
`SSH_PUBLIC_KEY` repository variable before planning. It is the public half
only; the private key never leaves the operator's workstation.

## Alternatives considered

### 1. Service principal with a client secret in GitHub Secrets

Rejected. A long-lived secret that can leak and must be rotated, which is the
risk this decision removes.

### 2. App registration with a federated credential

Rejected in favour of the managed identity. It works with OIDC, but an app
registration can also hold client secrets, and creating it needs Entra ID
permissions outside the subscription.

### 3. Federated credential for any branch (`repo:...:ref:refs/heads/*`)

Rejected. Anyone able to push a branch could add a workflow that obtains an
Azure token.

### 4. CI also runs `apply` after merge

Deferred. It needs write permissions (Contributor plus role assignment
rights), an approval step and a separate identity. Plan-only removes the main
risk, unreviewed changes, without giving the pipeline the ability to change
anything.

## Consequences

### Positive

- Every pull request shows its effect in Azure before merge.
- No Azure secret exists anywhere in GitHub.
- A compromised pipeline can read the subscription, but cannot change it.

### Negative

- **`Reader` on the subscription shows every resource's configuration.** A
  pull request that changes the workflow could print it in the public run log.
  Mitigation: only branches of this repository can obtain the token, and only
  collaborators can push branches; forks cannot.
- **The plan may need permissions beyond `Reader`.** Some resources read
  values that `Reader` cannot access. In testing, `Reader` plus the state role
  was enough for both roots. If a future resource needs more, grant the
  narrowest extra permission and document it here.
- **Apply is still manual,** so the operator can still apply something different
  from what was reviewed. Mitigation: apply only from `main` after merge.

## Future work

- Apply from CI after merge, with a separate write identity and a required approval.
- Post the plan summary as a comment on the pull request.
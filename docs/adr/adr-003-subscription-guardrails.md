# ADR-003: Subscription guardrails live in a separate Terraform root

- **Status:** Accepted
- **Date:** 2026-10-01
- **Deciders:** Jero Méndez
- **Supersedes:** —
- **Superseded by:** —

## Context

SEC-014 (issue #8) removed public network access from the project's Key Vault.
That fix lives in this repository's Terraform code, so it only protects the vault
this repository deploys. A vault created by anyone else, from the portal or
another pipeline, gets public network access enabled by default, and the audit
finding comes back unnoticed until the next audit (SEC-015).

Azure Policy can enforce the rule for every vault in a scope, regardless of who
creates it or which role they hold. Two questions had to be answered: at which
scope to assign it, and where the assignment's code should live.

The workload in this repository is deployed and destroyed in every lab session.

## Decision

1. Assign the built-in policy *Azure Key Vault should disable public network
   access* (`405c5871-3e91-4644-8a63-58e19d68ff5b`) at **subscription** scope.
2. Manage it from **`governance/`**, a separate Terraform root with its own
   state, not from the workload configuration.
3. Roll it out as **`Audit`** first and switch to **`Deny`** only when no
   non-compliant vaults remain. The effect is a validated variable
   (`Audit`, `Deny`, `Disabled`).
4. Reference the definition by its GUID, which is stable across tenants, not by
   its display name.

## Alternatives considered

### 1. Assign at resource group scope, inside the workload configuration

Rejected. It would only cover the resource group this repository already
configures correctly, so it adds almost nothing. Vaults created in other
resource groups, the actual risk, would not be covered.

### 2. Assign at subscription scope, inside the workload configuration

Rejected. Every `terraform destroy` of the lab would also delete the guardrail.
A control that disappears whenever the workload is torn down does not protect
anything.

### 3. Assign at management group scope

Correct for an organization with several subscriptions, and the production
target. Not applicable here: the lab has a single subscription and no
management group hierarchy.

### 4. Go straight to `Deny`

Rejected as a general practice. In an environment with existing vaults, `Deny`
does not break running vaults but blocks their next update, including routine
pipeline changes such as adding a tag. `Audit` first shows what would break.

## Consequences

### Positive

- Any create or update of a Key Vault with public network access is rejected
  with `RequestDisallowedByPolicy`, even for an `Owner`.
- The guardrail's lifecycle is independent of the workload's.
- The effect is changed through code review, like any other change.

### Negative

- **Two Terraform roots to operate.** Mitigation: `governance/` is small and
  rarely changes; CI validates both.
- **The guardrail can block legitimate needs.** Mitigation: a policy
  *exemption*, documented with an expiry date, instead of disabling the
  assignment.
- **Local state for governance**, like the workload. Remote state is already
  listed as future work.

## Future work

- More guardrails with the same pattern: Storage and SQL public network access,
  allowed locations, required tags.
- Remote state for both roots.
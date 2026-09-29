# ADR-002: Operators write Key Vault secrets from inside the VNet

- **Status:** Accepted
- **Date:** 2026-09-28
- **Deciders:** Jero Méndez
- **Supersedes:** —
- **Superseded by:** —

## Context

Security finding SEC-014 (issue #8) reports that `kv-securenet-dev-eus-001`
accepts connections from any address on the Internet. Access is currently
protected only by identity (Entra ID + RBAC). Company policy states that
services storing secrets must not be reachable from public networks.

The fix is a private endpoint in a dedicated subnet, a private DNS zone
(`privatelink.vaultcore.azure.net`) linked to the VNet, and public network
access disabled on the vault. After that change, the vault's data plane
(`*.vault.azure.net`, where secrets are read and written) only accepts
traffic that arrives through the VNet.

This breaks the current operator workflow. Secret values are deliberately
created outside Terraform, with Azure CLI from the operator's workstation, so
they never reach the state file. The workstation is on the Internet, not in
the VNet, so `az keyvault secret set` would be rejected with a network-level
403 after the change.

Terraform itself is not affected: it manages the vault through the management
plane (`management.azure.com`), which the vault's network rules do not
restrict.

## Decision

**Lab:** operators write secrets from `vm-mgmt`, inside the VNet.

1. Deploy Bastion for the session (`enable_bastion = true`).
2. Connect to `vm-mgmt` through Bastion.
3. Sign in with the operator's own identity (`az login --use-device-code`).
4. Write the secret with a shell-generated value and `--output none`.
5. Sign out (`az logout`) and disable Bastion again.

`vm-mgmt` is used instead of `vm-app` because operator credentials must not
be present on a workload server. If the application tier is compromised, an
operator token cached there would give the attacker write access to secrets.

**Production target:** private connectivity for people and automation, so no
interactive session on a shared VM is needed:

- Point-to-site VPN for operators.
- A CI runner inside the VNet, authenticated with OIDC, for automated secret
  rotation.

## Alternatives considered

### 1. Write secrets from inside the VNet (Bastion + `vm-mgmt`)

Chosen for the lab. It meets the policy with components that already exist in
this environment and adds no new public exposure.

### 2. Key Vault firewall allowing the operator's public IP

Rejected. The vault would remain reachable from a public network, which the
policy prohibits, and Checkov `CKV_AZURE_189` would keep failing. Home IP
addresses change without notice, so access would break unpredictably and the
rule would need constant manual updates.

### 3. Enable public access temporarily, write the secret, disable it again

Rejected. Every write becomes a manual change outside Terraform (drift) and
opens an exposure window. The control depends on someone remembering to close
it.

### 4. Point-to-site VPN or a CI runner inside the VNet

Deferred as the production target. It is the correct long-term design, but a
VPN gateway and runner infrastructure add cost and operational work that this
lab does not justify yet.

## Consequences

### Positive

- The vault's data plane is no longer reachable from the Internet. A leaked
  token cannot be used from outside the VNet: an attacker needs both a valid
  identity and a network position inside the VNet.
- Resolves the `TEMPORARY` Checkov skips tracked in #8 (`CKV_AZURE_189`,
  `CKV_AZURE_109`, `CKV2_AZURE_32`).
- `vm-app` keeps reading its secret through the private endpoint with no
  change to its identity or role.

### Negative

- **Each secret write requires Bastion, which bills per hour.** Mitigation:
  secret writes are rare, and Bastion is enabled only for the session and
  destroyed afterwards.
- **An operator token is temporarily cached on a shared VM.** Mitigation: the
  VM is in the management tier, access to it requires Bastion plus RBAC, and
  the operator signs out at the end of every session.
- **`vm-mgmt` needs Azure CLI installed.** Mitigation: installed on demand for
  now; cloud-init is future work.
- **Troubleshooting from the workstation is no longer possible.** Reading a
  secret to debug also has to go through `vm-mgmt`. This is intended.

## Future work

- Point-to-site VPN for operator access (production target, alternative 4).
- CI runner inside the VNet with OIDC for secret rotation.
- Install Azure CLI on `vm-mgmt` with cloud-init instead of manually.
- Alert on network-level denials in the Key Vault audit logs.
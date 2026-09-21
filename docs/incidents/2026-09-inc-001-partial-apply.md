# INC-001: Partial Terraform apply during naming refactor

| Field       | Value                                          |
|-------------|------------------------------------------------|
| Date        | 2026-09-21                                     |
| Environment | dev (lab)                                      |
| Severity    | Low — lab environment, no users or workloads affected |
| Status      | Resolved                                       |
| Author      | jeromendezb                                    |

## Summary

During the refactor to the Microsoft Cloud Adoption Framework (CAF) naming
convention, `terraform apply` failed partway through. All new resources were
created successfully, but the legacy resources were only partially destroyed,
leaving the old resource group `rg-terraform-lab1` orphaned in Azure and still
tracked in the Terraform state.

## Impact

- **No service impact:** lab environment with no workloads deployed.
- **New network created correctly:** `rg-securenet-dev-eus-001`,
  `vnet-securenet-dev-eus-001`, `snet-app`, `snet-mgmt`.
- **Inconsistent state:** after the failed apply, `azurerm_resource_group.grupo_lab1`
  and `azurerm_subnet.subnet1` remained in the Terraform state, and the legacy
  resource group remained in Azure (empty).
- **Risk if left unresolved:** orphaned resources, divergence between state and
  reality, and ambiguity about which network is authoritative.

## Timeline

1. `terraform plan` proposed `4 to add, 4 to destroy` (renaming forces resource
   replacement in Azure).
2. `terraform apply` started. The legacy subnets **and** the legacy VNet began
   destroying **at the same time**. New resources were created in the correct
   order (resource group → VNet → subnets).
3. Apply failed with `404 ResourceNotFound` while deleting `subnet1_terraform_lab1`:
   its parent VNet `vnet_terraform_lab1` no longer existed.
4. Verification with `az group list` showed `rg-terraform-lab1` still present.
5. Investigation:
   - `az group show ... provisioningState` → `Succeeded` (not a deletion in progress).
   - `terraform state list` → legacy resource group and `subnet1` still tracked.
   - `az resource list` on the legacy group → empty (no unmanaged resources blocking deletion).
6. Re-ran `terraform plan`. The refresh detected that `subnet1` no longer existed
   and removed it from state. The plan proposed `1 to destroy` (the legacy resource group).
7. `terraform apply` destroyed the legacy resource group. Verified with
   `az group list`: only `rg-securenet-dev-eus-001` remains.

## Root cause

The legacy configuration referenced the parent VNet with a variable string
instead of a resource reference:

```hcl
# Legacy (buggy): no dependency between subnet and VNet
virtual_network_name = var.virtual_network_name
```

Terraform builds its dependency graph from resource references. With a plain
string, Terraform had no way to know that the subnets depended on the VNet, so it
destroyed subnets and VNet **in parallel**. Azure finished deleting the VNet —
and its subnets with it — before the delete request for `subnet1` completed. That
request then failed with `404` because its parent no longer existed. Since the
resource group depended on `subnet1`, Terraform skipped destroying it.

**Evidence:** the apply log shows the three `Destroying...` lines starting
simultaneously, followed by the `404` error referencing the missing parent VNet.

The bug was **latent**: creating the resources had always succeeded, and the
missing dependency only surfaced during destruction.

## Resolution

Re-ran `terraform plan` so that the refresh reconciled the state with the real
infrastructure, then applied the remaining destroy. **No manual changes were made
in the Azure Portal**, to avoid introducing drift between state and reality.

## Contributing factors

- The output of the first apply was not reviewed immediately, which delayed
  identifying the root cause.

## Preventive actions

| Action | Status |
|--------|--------|
| Use resource references (not string variables) for every parent/child relationship, e.g. `azurerm_virtual_network.main.name` | Done |
| Run `terraform fmt` and `terraform validate` before every plan | Adopted |
| Review every `destroy` line of a plan before applying | Adopted |
| Keep the full plan/apply output for any change that destroys resources | Adopted |
| Run plan/apply from a CI/CD pipeline, which retains logs automatically | Planned |

## Lessons learned

- Terraform does **not** roll back a failed apply. Whatever completed stays
  completed, and the state records it. The correct recovery is to re-run
  `terraform plan`, not to fix things by hand in the Portal.
- Implicit dependencies come from resource references. Hard-coded names hide
  dependencies and create race conditions that may only appear intermittently.

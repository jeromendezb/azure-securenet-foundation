# Evidence: NSG on AzureBastionSubnet

**Date:** 2026-10-01
**Issue:** #9
**Objective:** Attach an NSG to `AzureBastionSubnet` with the rules Azure
Bastion requires, and verify that administrative access through Bastion still
works.

## Setup

- `nsg-bastion-securenet-dev-eus-001` associated with `AzureBastionSubnet`.
- Rules taken from Microsoft's documentation, *Working with NSG access and
  Azure Bastion*. Unlike the other NSGs in this project, these rules are not a
  design choice: Bastion stops working if any of them is missing.
- The NSG and its association exist even when Bastion is disabled
  (`enable_bastion = false`). The subnet always exists, so its protection
  should too, and an NSG has no cost.
- `azurerm_bastion_host` has an explicit `depends_on` on the NSG association,
  to avoid the same race condition found in #13 (both resources modify the
  same subnet).
- Deployed from an empty environment with `enable_bastion = true`.

## Rules as deployed in Azure

`az network nsg rule list ... -o table`:

| Name | Priority | Direction | Protocol | Source | Destination | Ports |
|---|---|---|---|---|---|---|
| AllowHttpsInbound | 120 | Inbound | Tcp | Internet | * | 443 |
| AllowGatewayManagerInbound | 130 | Inbound | Tcp | GatewayManager | * | 443 |
| AllowAzureLoadBalancerInbound | 140 | Inbound | Tcp | AzureLoadBalancer | * | 443 |
| AllowBastionHostCommunication | 150 | Inbound | * | VirtualNetwork | VirtualNetwork | 8080, 5701 |
| AllowSshRdpOutbound | 100 | Outbound | * | * | VirtualNetwork | 22, 3389 |
| AllowAzureCloudOutbound | 110 | Outbound | Tcp | * | AzureCloud | 443 |
| AllowBastionCommunication | 120 | Outbound | * | VirtualNetwork | VirtualNetwork | 8080, 5701 |
| AllowHttpOutbound | 130 | Outbound | * | * | Internet | 80 |

**Design decision:** `AllowHttpsInbound` allows the whole Internet, not a fixed
IP range. Operators connect from dynamic addresses (see ADR-001), and reaching
port 443 grants nothing on its own: a session still requires Entra ID
authentication, an RBAC role on the target VM and the SSH private key.

## Results

| # | Test | Result |
|---|---|---|
| 1 | Deploy from an empty environment with Bastion enabled | ✅ No race condition |
| 2 | Rules in Azure match the documented requirements | ✅ 8/8 |
| 3 | SSH session to `vm-app` through Bastion | ✅ Connected |
| 4 | `terraform plan` after apply | ✅ `No changes` |

## Test 3: SSH session through Bastion

```
azureadmin@vm-app-securenet-dev-eus-001:~$ who
azureadmin pts/0        2026-10-01 15:21 (10.0.3.5)
azureadmin@vm-app-securenet-dev-eus-001:~$ hostname
vm-app-securenet-dev-eus-001
```

The session source is `10.0.3.5`, an address inside `AzureBastionSubnet`
(`10.0.3.0/26`). The VM sees Bastion as the client, not the operator's public
IP. This confirms the full path still works with the NSG in place: Internet →
HTTPS 443 → Bastion → SSH over the private network → `vm-app`.

## Findings

1. **Source port vs destination port.** The first draft of `AllowHttpsInbound`
   had the ports reversed (`source_port_range = "443"`,
   `destination_port_range = "*"`). Clients connect from random source ports,
   so legitimate traffic would never have matched and Bastion would have been
   unreachable. Worse, the rule would have allowed Internet traffic to any port
   in the subnet as long as the sender chose source port 443. `terraform
   validate` and Checkov did not flag it; it was caught in code review.
2. **A rule that matches the documentation in a table can still be wrong in
   code.** `AllowAzureCloudOutbound` was first written with destination
   `VirtualNetwork` instead of `AzureCloud`. Comparing the deployed rules
   against the documented table (above) is part of the verification.
3. **No `TEMPORARY` Checkov exceptions remain.** The four remaining skips are
   accepted risks with written justification (purge protection, VM
   extensions).
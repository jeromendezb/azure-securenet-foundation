# ADR-001: Use Azure Bastion as the only administrative access path to VMs

- **Status:** Accepted
- **Date:** 2026-09-23
- **Deciders:** Jero Méndez
- **Supersedes:** —
- **Superseded by:** —

## Context

The SecureNet environment runs two workload subnets inside a single VNet:
`snet-app` (application servers) and `snet-mgmt` (management servers).
Both host Linux VMs that operators need to administer over SSH for
configuration, patching and troubleshooting.

Administrative access has to exist, but the servers must not be reachable
from the Internet. A VM with a public IP and port 22 or 3389 open is
scanned within minutes of being created and becomes the entry point for
credential-stuffing and ransomware campaigns. Once an attacker lands on one
host, flat networking lets them move laterally to the rest of the
environment.

Operators connect from changing locations (home, office, travel), so any
solution that depends on a fixed source address is operationally fragile.
The environment is a lab that models a client deployment, so the chosen
mechanism must be something a small team can run without dedicated network
staff.

## Decision

Administrative access to all VMs goes exclusively through **Azure Bastion**,
deployed in the mandatory `AzureBastionSubnet` (`10.0.3.0/26`).

No VM in the environment has a public IP address. Operators authenticate to
the Azure portal, and Bastion brokers the SSH session over TLS from inside
the VNet, so port 22 is never exposed to the Internet.

Two NSG rules enforce that Bastion is the *only* path, and are therefore
part of this decision rather than a separate one:

- `snet-app`, priority 100: deny inbound TCP 22 and 3389 from the `Internet`
  service tag.
- `snet-mgmt`, priority 100: deny all inbound traffic originating from
  `10.0.1.0/24` (`snet-app`).

Priority 100 places both rules above Azure's default `AllowVnetInBound`
(65000), which would otherwise permit any VNet-internal traffic between the
two subnets.

## Alternatives considered

### 1. Public IP on each VM with SSH/RDP open

Rejected. It is the fastest option and requires no extra infrastructure, but
it exposes the management ports to the whole Internet. Automated scanners
find these hosts continuously, and a single weak or reused credential
compromises the environment. It also puts an Internet-facing attack surface
on every VM, so the exposure grows linearly with the number of servers.

### 2. Public IP restricted by source IP range

Rejected. Filtering SSH to a known office range is a real improvement over
option 1, but operators connect from residential connections with dynamic
addresses, from mobile networks and from hotel networks while travelling.
Keeping the allowlist accurate would mean editing NSG rules on demand, which
in practice degrades into a permanently over-broad rule ("allow the whole
ISP range") or into admins locked out during an incident — the worst
possible moment. The control depends on a property (a stable source address)
that this team does not have.

### 3. Site-to-site or point-to-site VPN

Rejected for this environment. It is the correct answer at a larger scale
and removes the public exposure properly, but it adds a gateway to deploy
and maintain, certificate or credential lifecycle management, and VPN client
software installed and supported on every administrator's machine. For a
two-subnet environment administered by a small team, the operational
overhead and cost exceed the benefit over Bastion.

### 4. Just-in-Time VM Access (Microsoft Defender for Cloud)

Not adopted now. JIT opens the management port only for a requested window
and a requested source address, which reduces exposure substantially. It
still relies on a public IP being present and requires a Defender for Cloud
plan. It remains a reasonable complement if VMs ever need direct access for
a reason Bastion cannot serve.

## Consequences

### Positive

- No VM in the environment has a public IP; SSH is not reachable from the
  Internet at all, so the exposed attack surface for management protocols is
  zero rather than merely restricted.
- Access is tied to Azure AD identity and Azure RBAC, so it inherits MFA,
  conditional access and central revocation. Removing an operator from the
  directory removes their access to every VM at once.
- Sessions are brokered over TLS through the browser, so operators need no
  VPN client or local SSH configuration.
- The NSG rules contain lateral movement: a compromised application server
  cannot reach the management subnet, so the blast radius of an application
  compromise stops at `snet-app`.

### Negative

- **Fixed cost even when idle.** Bastion is billed per hour of deployment
  (Basic SKU, roughly USD 0.19/hour, about USD 140/month) plus outbound data,
  whether or not anyone connects. In a lab this dominates the bill, which is
  why the environment is destroyed between sessions.
- **Single point of dependency.** The control and the bottleneck are the same
  component. If Bastion is unavailable or misconfigured, there is no
  administrative access to any VM, including during an incident. A documented
  break-glass procedure is required before this design goes to production.
- **Addressing cost from day one.** Bastion requires a dedicated subnet
  named exactly `AzureBastionSubnet` with a minimum size of `/26`. That
  consumes 64 addresses and fixes part of the address plan before any
  workload exists. Resizing it later means redeploying Bastion.
- Bastion Basic does not support native client connections or file transfer;
  those require the Standard SKU at higher cost.

## Future work

- **Egress control (ADR-002 candidate).** VMs currently reach the Internet
  outbound for package updates. An internal package mirror or an Azure
  Firewall with an FQDN allowlist would remove that path and close the
  remaining direct exposure to the Internet.
- **Break-glass procedure.** Define and test how administrators reach the
  VMs if Bastion is unavailable, before this pattern is used in production.
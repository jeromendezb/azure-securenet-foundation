# Evidence: Break-glass access without SSH or Bastion

**Date:** 2026-10-01
**Issue:** #2
**Objective:** Verify that the procedures in the
[break-glass runbook](../runbooks/break-glass-vm-access.md) recover access to a
VM when the normal path (Bastion → SSH) is unavailable.

## Setup

- Environment deployed **without Bastion** (`enable_bastion = false`), which is
  itself case A of the runbook.
- `boot_diagnostics {}` added to both VMs (Azure-managed storage).
- All commands ran with Azure CLI from the operator's workstation; outputs were
  captured with `Tee-Object` while running.

## Results

| # | Case | Test | Result |
|---|---|---|---|
| 1 | C | SSH reachable from `vm-mgmt` before the fault | ✅ `OPEN` |
| 2 | C | Host firewall enabled on `vm-app` (`ufw default deny incoming`) | ✅ SSH `CLOSED or filtered` |
| 3 | C | Firewall disabled through `run-command`, no network path used | ✅ SSH `OPEN` again |
| 4 | B | Emergency key installed with VMAccess | ✅ Present in `authorized_keys` (`1`) |
| 5 | D | Boot log read without logging in | ✅ Full boot log |
| 6 | — | Every `run-command` recorded in the Activity Log | ✅ 6 of 6, caller = operator |
| — | D | Repair VM (`az vm repair`) | ⚠️ Not tested |

## Case C: SSH broken inside the VM, fixed without SSH

```
SSH port 22 on 10.0.1.4: OPEN
Default incoming policy changed to 'deny'
Firewall is active and enabled on system startup
SSH port 22 on 10.0.1.4: CLOSED or filtered (no answer within 5 s)
Firewall stopped and disabled on system startup
SSH port 22 on 10.0.1.4: OPEN
```

Nobody could reach `vm-app` over SSH between the second and fourth lines. The
fix went through the Azure VM agent, which does not use the VM's network path.

## Case B: emergency key

```
1
```

`grep -c breakglass` on `authorized_keys` after `az vm user update`. The
original key was not removed.

## Case D: boot log without login

Last lines of `az vm boot-diagnostics get-boot-log`:

```
[  OK  ] Reached target cloud-init.target - Cloud-init target.
Ubuntu 24.04.4 LTS vm-app-securenet-dev-eus-001 ttyS0
vm-app-securenet-dev-eus-001 login:
```

The serial console login prompt is present. Serial Console is not used only
because the VMs have no local password, a deliberate decision.

## Audit trail

```
Time                          Caller
----------------------------  ------------------------------
2026-10-01T17:17:22.5629886Z  <operator>
2026-10-01T17:14:41.1839423Z  <operator>
2026-10-01T17:14:05.7656839Z  <operator>
2026-10-01T17:13:41.5278299Z  <operator>
2026-10-01T17:12:57.1211497Z  <operator>
2026-10-01T17:12:21.1805099Z  <operator>
```

Six successful `runCommand` operations, matching the six executed.

## Findings

1. **`run-command` bypasses the network entirely.** It recovered a VM with SSH
   blocked, and it would equally let anyone with the permission run commands
   as root. `Virtual Machine Contributor` includes that permission. This is
   access to restrict and alert on, not only a recovery tool.
2. **The default Activity Log query hid five of six executions.**
   `az monitor activity-log list` returns the 50 most recent events of the
   resource group by default, and `--query` filters *after* that cut. The first
   query showed one `run-command`; with `--max-events 1000` it showed six. A
   filter applied to a truncated list fails silently, and an investigation
   based on it would have concluded the action happened once.
3. **The boot log exposes environment details**: SSH host key fingerprints and
   authorized key fingerprints. Not secrets, but access to boot diagnostics
   should be limited like any other operational data.
4. **On Windows, `az` is a `.cmd` wrapper**, so `&&`, `||` and `<` in inline
   scripts are interpreted by the Windows shell. Inline commands were kept
   free of them, and the reachability check runs from a script file.
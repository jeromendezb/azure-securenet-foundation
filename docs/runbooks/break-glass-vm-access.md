# Runbook: Break-glass access to the SecureNet VMs

- **Applies to:** `vm-app-securenet-dev-eus-001`, `vm-mgmt-securenet-dev-eus-001`
- **Owner:** Jero Méndez
- **Last tested:** 2026-10-01 ([evidence](../evidence/break-glass-test.md))
- **Related:** issue #2, [ADR-001](../adr/adr-001-bastion-for-admin-access.md)

## When to use this runbook

Use it when the normal path (Azure Bastion → SSH with the operator's key) does
not work and someone needs to inspect or fix a VM. Every action below runs as
**root** on the VM or changes its access, so it is an incident action: record
who did what, when and why.

## Before you start

1. **Open an incident record** (ticket or issue): time, symptom, who is acting.
2. **Check your permissions.** You need a role that includes
   `Microsoft.Compute/virtualMachines/runCommand/action` and extension write
   access on the VM (in this lab: the operator's `Owner` role).
3. **Set the variables** in PowerShell:

```powershell
$RG   = "rg-securenet-dev-eus-001"
$APP  = "vm-app-securenet-dev-eus-001"
$MGMT = "vm-mgmt-securenet-dev-eus-001"
```

4. **Check that the VM agent is responding.** Every tool except boot
   diagnostics and the repair VM depends on it:

```powershell
az vm get-instance-view -g $RG -n $APP --query "instanceView.vmAgent.statuses[0].displayStatus" -o tsv
```

`Ready` → cases A–C. Anything else → case D.

## Pick the case

| Symptom | Case | Tool | Needs network/SSH | Needs VM agent |
|---|---|---|---|---|
| Bastion unavailable (down, deleted or disabled) | A | `az vm run-command` | No | Yes |
| Operator's SSH private key lost | B | VMAccess (`az vm user update`) | No | Yes |
| VM running, SSH not answering | C | `az vm run-command` | No | Yes |
| VM not booting, or agent not `Ready` | D | Boot diagnostics, then `az vm repair` | No | No |

## Case A — Bastion unavailable

Run diagnostics or fixes through the VM agent:

```powershell
az vm run-command invoke -g $RG -n $APP --command-id RunShellScript --scripts "systemctl status ssh --no-pager" --query "value[0].message" -o tsv
```

If interactive access is required, redeploy Bastion from code:
`terraform apply -var="enable_bastion=true"` (about 10 minutes).

**Notes on `run-command`:** it runs as root, one command set at a time per VM,
and returns only the last part of the output (about 4 KB). For longer output,
write to a file on the VM and read it in pieces.

On Windows, `az` is a `.cmd` wrapper: characters such as `&&`, `||` and `<` in
`--scripts` are interpreted by the Windows shell before they reach Azure. Put
anything beyond a simple command in a script file and pass it as
`--scripts "@path/to/script.sh"`.

## Case B — SSH private key lost

1. Create an emergency key **with a passphrase**:

```powershell
ssh-keygen -t ed25519 -f "$HOME\.ssh\securenet_breakglass" -C "breakglass"
```

2. Install it with the VMAccess extension (adds the key; the existing key stays):

```powershell
az vm user update -g $RG -n $APP -u azureadmin --ssh-key-value "$HOME\.ssh\securenet_breakglass.pub" -o none
```

3. Verify (expected output: `1`):

```powershell
az vm run-command invoke -g $RG -n $APP --command-id RunShellScript --scripts "grep -c breakglass /home/azureadmin/.ssh/authorized_keys" --query "value[0].message" -o tsv
```

4. Connect through Bastion with the new key.

## Case C — VM running, SSH not answering

1. Confirm from another VM in the VNet (expected: `CLOSED or filtered`):

```powershell
az vm run-command invoke -g $RG -n $MGMT --command-id RunShellScript --scripts "@scripts/check-ssh-port.sh" --query "value[0].message" -o tsv
```

2. Find the cause through the agent:

```powershell
az vm run-command invoke -g $RG -n $APP --command-id RunShellScript --scripts "ufw status verbose" "systemctl is-active ssh" "df -h /" --query "value[0].message" -o tsv
```

3. Fix the cause. Examples:
   - Host firewall blocking: `--scripts "ufw --force disable"`
   - SSH service stopped: `--scripts "systemctl restart ssh"`
   - Disk full: free space, then restart the service.
4. Repeat step 1. Expected: `OPEN`.

## Case D — VM not booting, or agent not responding

`run-command` and VMAccess both depend on the VM agent and will not work here.

1. Read the boot log without logging in:

```powershell
az vm boot-diagnostics get-boot-log -g $RG -n $APP | Select-Object -Last 40
```

2. If the cause needs changes on disk, use a repair VM (**not tested in this
   lab**). It copies the OS disk, attaches it to a temporary VM for repair, and
   swaps it back:

```powershell
az extension add -n vm-repair
az vm repair create  -g $RG -n $APP --verbose
# fix the attached disk from the repair VM, then:
az vm repair restore -g $RG -n $APP --verbose
```

3. As a last resort, redeploy the VM from code. Anything stored only on the VM
   is lost.

**Why not Serial Console:** it works without the agent, but needs a local user
password. Keeping one would add a secret to store, rotate and monitor for this
case only. The accepted trade-off is a slower recovery for case D.

## After the incident

1. **Remove the emergency key** if one was added (expected output: `0`):

```powershell
az vm run-command invoke -g $RG -n $APP --command-id RunShellScript --scripts "sed -i '/breakglass/d' /home/azureadmin/.ssh/authorized_keys" "grep -c breakglass /home/azureadmin/.ssh/authorized_keys"
```

2. **Revert any temporary change** (for example, re-enable the host firewall
   with the correct rules).
3. **Review the audit trail.** Every `run-command` is in the Activity Log. Use
   `--max-events`: the default returns only the 50 most recent events of the
   resource group, and the filter runs after that cut, so older executions
   silently disappear from the result.

```powershell
az monitor activity-log list -g $RG --offset 6h --max-events 1000 --query "[?contains(operationName.value, 'runCommand') && status.value=='Succeeded'].{time:eventTimestamp, caller:caller}" -o table
```

4. **Write the incident report** in `docs/incidents/`.
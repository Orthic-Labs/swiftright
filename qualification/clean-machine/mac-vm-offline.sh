#!/bin/bash
# mac-vm-offline.sh - take a Tart guest offline before mac-clean-run.sh (R7's method). Runs OUTSIDE the harness.
#
# Removes every default route (v4 and v6, scoped and unscoped) so the guest cannot reach the network; the on-link subnet
# stays up, so SSH keeps working. A runtime routing-table change only: nothing persists across a reboot, and the harness
# itself never changes a system setting. Refuses unless the machine is a virtual machine (kern.hv_vmm_present=1 and
# hw.model=VirtualMac*), so it can never cut the host Mac off. Needs passwordless sudo (the Tart guest's admin has it).
#
#   bash mac-vm-offline.sh        # prints "offline: no default routes" or exits 1
set -u
export LC_ALL=C
[ "$(sysctl -n kern.hv_vmm_present 2>/dev/null)" = 1 ] || { echo "mac-vm-offline: not a VM (kern.hv_vmm_present)" >&2; exit 2; }
case "$(sysctl -n hw.model 2>/dev/null)" in VirtualMac*) ;; *) echo "mac-vm-offline: not a Virtualization.framework guest (hw.model)" >&2; exit 2 ;; esac
sudo -n true 2>/dev/null || { echo "mac-vm-offline: passwordless sudo is required" >&2; exit 2; }

defaults() { netstat -rn 2>/dev/null | awk '$1=="default" {n++} END {print n+0}'; }
for i in 1 2 3 4 5 6 7 8; do
  sudo -n route -n delete default >/dev/null 2>&1
  sudo -n route -n delete -inet6 default >/dev/null 2>&1
  for ifc in $(ifconfig -l); do
    sudo -n route -n delete default -ifscope "$ifc" >/dev/null 2>&1
    sudo -n route -n delete -inet6 default -ifscope "$ifc" >/dev/null 2>&1
  done
  [ "$(defaults)" -eq 0 ] && break
  sleep 1
done
if [ "$(defaults)" -eq 0 ]; then
  echo "offline: no default routes (v4 or v6)"
  exit 0
fi
echo "mac-vm-offline: default routes remain:" >&2
netstat -rn | awk '$1=="default"' >&2
exit 1

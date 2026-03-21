---
name: ssh-debug
description: Debug remote servers via SSH with profile-based diagnostics. Profiles available - linux (base), k8s-worker, ceph, proxmox. Use when user says check server, check host, check node, server health, node health, SSH into, connect to, check logs on, check disk on, check memory on, OOM on host, server down, node not ready, kubelet issues, containerd issues, ceph health, ceph status, ceph OSD, MDS caps, MDS recall, proxmox VMs, VM memory, overcommit, dmesg errors, systemd failed, service crashed, disk pressure, disk full, investigate host, debug server, what's wrong with host/server/node.
allowed-tools:
  - Bash(/Users/ninja/.claude/skills/ssh-debug/ssh-debug:*)
  - Read(/Users/ninja/ordercapital/ceph/*)
---

# SSH Debug Skill

Profile-based SSH debugging. All operations are **read-only**. All output is AI-optimized JSON.

**Host is always the first argument** after the script name. This enables per-host permission matching in Claude Code settings.

## Permission Model

- `ssh-debug` (base linux) is auto-approved via `allowed-tools` above
- Profile scripts (`ssh-debug-k8s-worker`, etc.) are NOT auto-approved
- First use of a profile script on a new host triggers a Claude Code permission prompt
- User approves "always" → settings gets `Bash(/path/ssh-debug-k8s-worker hostname:*)`
- **After incident**: remind user to remove profile+host entries from their settings

## Base Linux Profile

```bash
/Users/ninja/.claude/skills/ssh-debug/ssh-debug <host> status
/Users/ninja/.claude/skills/ssh-debug/ssh-debug <host> disk [path]
/Users/ninja/.claude/skills/ssh-debug/ssh-debug <host> logs <unit> [-n N]
/Users/ninja/.claude/skills/ssh-debug/ssh-debug <host> dmesg [-n N]
/Users/ninja/.claude/skills/ssh-debug/ssh-debug <host> network
```

| Command | What it does |
|---------|-------------|
| `status` | uptime, load, memory, failed systemd units |
| `disk [path]` | df -h /; default du on /var/log + /tmp; or du on specific path (allowed: /var/log, /var/log/journal, /tmp, /opt, /var/lib, /var/spool) |
| `logs <unit> [-n N]` | journalctl for any systemd unit (default: 100 lines) |
| `dmesg [-n N]` | kernel err/warn messages (default: 50 lines) |
| `network` | ip -br addr, ss -tlnp listeners, ip route |

## K8s Worker Profile

```bash
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-k8s-worker <host> status
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-k8s-worker <host> config [kubelet|containerd|all]
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-k8s-worker <host> logs [kubelet|containerd] [-n N]
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-k8s-worker <host> containers
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-k8s-worker <host> dmesg [-n N]
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-k8s-worker <host> disk [path]
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-k8s-worker <host> ephemeral <kubectl-context> [--top N]
```

| Command | What it does |
|---------|-------------|
| `status` | kubelet + containerd is-active check, uptime, memory |
| `config [target]` | read kubelet/containerd config files |
| `logs [service] [-n N]` | kubelet/containerd journal logs (errors on unknown service) |
| `containers` | crictl images (top 20 by size), container state counts, overlayfs snapshot count |
| `dmesg [-n N]` | kernel err/warn messages |
| `disk [path]` | df -h /; default du /var/log + /tmp; or du on path (allowed: /var/lib/containerd, /var/lib/kubelet, /var/lib/docker, /var/log, /var/log/pods, /var/log/journal, /tmp, /opt) |
| `ephemeral <ctx> [--top N]` | top pods by ephemeral storage via kubelet stats API |

## Ceph Profile

Run on a ceph monitor node. All `ceph` commands via `sudo -n`.

```bash
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-ceph <host> health
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-ceph <host> osd
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-ceph <host> mds [filesystem]
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-ceph <host> mds-clients <mds-daemon> [client-id]
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-ceph <host> mds-ops <mds-daemon>
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-ceph <host> mds-perf <mds-daemon>
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-ceph <host> mds-subtrees <mds-daemon>
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-ceph <host> config <who> [key]
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-ceph <host> log [-n N]
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-ceph <host> pg
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-ceph <host> blocklist
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-ceph <host> disk [path]
```

| Command | What it does |
|---------|-------------|
| `health` | ceph status (JSON) + ceph health detail |
| `osd` | osd tree, osd df, pool stats (all JSON) |
| `mds [fs]` | MDS stat, fs status, optional fs dump |
| `mds-clients <daemon> [id]` | MDS client sessions or specific client cap dump |
| `mds-ops <daemon>` | ops in flight on MDS daemon |
| `mds-perf <daemon>` | perf counters: caps, inodes, request rate (summary + full dump) |
| `mds-subtrees <daemon>` | MDS subtree partition map |
| `config <who> [key]` | ceph config dump or get specific key |
| `log [-n N]` | ceph log last N warnings (default: 20) |
| `pg` | PG stats + stuck unclean PGs |
| `blocklist` | blocklisted clients |
| `disk [path]` | df + du on /var/lib/ceph, /var/log/ceph |

MDS daemon names look like `mds.dm-fast.ceph-osd-fast-02.hsdari` — get them from `mds` command output.

## Proxmox Profile

Run on a Proxmox VE hypervisor host. Key feature: `vms` command scans KVM processes to show allocated vs actual (RSS) memory and detect overcommit.

```bash
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-proxmox <host> status
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-proxmox <host> vms
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-proxmox <host> vm <vmid>
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-proxmox <host> storage
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-proxmox <host> cluster
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-proxmox <host> dmesg [-n N]
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-proxmox <host> disk [path]
/Users/ninja/.claude/skills/ssh-debug/ssh-debug-proxmox <host> logs [service] [-n N]
```

| Command | What it does |
|---------|-------------|
| `status` | uptime, load, memory, failed units, PVE version |
| `vms` | all VMs: allocated vs RSS memory, cpu, storage type (shared-ssd/local-ssd-encrypted), overcommit summary |
| `vm <vmid>` | single VM config + status via `sudo qm` |
| `storage` | pvesm status + df for all mounts |
| `cluster` | pvecm status + node list |
| `dmesg [-n N]` | kernel err/warn messages (default: 50) |
| `disk [path]` | df + du (allowed: /var/lib/vz, /var/lib/pve, /var/log, /var/log/pve, /tmp, /etc/pve) |
| `logs [service] [-n N]` | journalctl for PVE services (default: pvedaemon, 100 lines) |

Available log services: pvedaemon, pveproxy, pvestatd, pve-cluster, pve-ha-lrm, pve-ha-crm, pve-firewall, corosync, ceph-mon, ceph-osd.

## Investigation Playbooks

### General Server Issue

1. `ssh-debug <host> status` — quick health check
2. `ssh-debug <host> disk` — filesystem pressure
3. `ssh-debug <host> dmesg` — kernel errors
4. `ssh-debug <host> network` — connectivity issues

### DiskPressure on K8s Node

1. `ssh-debug <host> status` — overall health
2. `ssh-debug-k8s-worker <host> status` — kubelet/containerd health
3. `ssh-debug-k8s-worker <host> disk` — filesystem overview
4. `ssh-debug-k8s-worker <host> ephemeral <ctx>` — per-pod ephemeral usage
5. `ssh-debug-k8s-worker <host> containers` — image cache bloat
6. `ssh-debug-k8s-worker <host> config kubelet` — eviction thresholds

### Ceph Cluster Degradation

1. `ssh-debug-ceph <mon> health` — cluster health + status overview
2. `ssh-debug-ceph <mon> osd` — OSD tree, utilization, pool stats
3. `ssh-debug-ceph <mon> pg` — PG state, stuck PGs
4. `ssh-debug-ceph <mon> log -n 50` — recent cluster warnings
5. `ssh-debug-ceph <mon> blocklist` — blocked clients

### CephFS MDS Cap Pressure (MDS_CLIENT_RECALL)

1. `ssh-debug-ceph <mon> health` — check for MDS_CLIENT_RECALL warnings
2. `ssh-debug-ceph <mon> mds <fs>` — MDS status, active/standby daemons
3. `ssh-debug-ceph <mon> mds-perf <daemon>` — cap counts, inode stats, request rate
4. `ssh-debug-ceph <mon> mds-clients <daemon>` — list all client sessions
5. `ssh-debug-ceph <mon> mds-clients <daemon> <client-id>` — cap dump for offending client
6. `ssh-debug-ceph <mon> mds-ops <daemon>` — ops in flight
7. `ssh-debug-ceph <mon> config mds mds_cache_memory_limit` — check cache limit
8. `ssh-debug-ceph <mon> config mds mds_max_caps_per_client` — check cap limits
9. `ssh-debug <mon> dmesg` — kernel errors on monitor node

### Proxmox Host Out of Memory

1. `ssh-debug <host> status` — quick health check, free memory
2. `ssh-debug-proxmox <host> status` — PVE version, failed units
3. `ssh-debug-proxmox <host> vms` — all VMs: allocated vs RSS, overcommit summary
4. `ssh-debug-proxmox <host> vm <vmid>` — drill into specific VM config
5. `ssh-debug <host> dmesg` — check for OOM killer events

### Ceph Monitor Disk Space

1. `ssh-debug <mon> status` — monitor node health
2. `ssh-debug-ceph <mon> disk` — /var/lib/ceph + /var/log/ceph usage
3. `ssh-debug <mon> disk /var/lib` — broader disk breakdown

## Adding New Profiles

Create a new executable `ssh-debug-<profile>` in this directory. Follow the same patterns:
- Host as first argument
- Command as second argument
- JSON output with `{"host", "profile", "command", ...}`
- Host validation via `HOST_RE`
- `sudo -n` for privileged commands
- Do NOT add it to `allowed-tools` — let Claude Code permission prompts handle per-host auth

## Output Format

All commands return structured JSON:
```json
{
  "host": "srv013.hel.vm.ordercapital.com",
  "profile": "linux",
  "command": "status",
  "uptime": "16:23:45 up 45 days...",
  "memory": "              total ...",
  "load": "0.15 0.10 0.05 1/234 5678",
  "failed_units": ""
}
```

## Permission Cleanup

After an incident is resolved, remind the user to clean up temporary permissions:

> The investigation is complete. You may want to remove the SSH debug permissions added during this session from your settings. Check `~/.claude/settings.json` or project `.claude/settings.json` for entries like `Bash(ssh-debug-k8s-worker hostname:*)` and remove ones that are no longer needed.

## Tips

1. Always start with `ssh-debug <host> status` for a quick health overview
2. Use profile-specific commands for deeper role-specific investigation
3. Combine with prometheus skill for historical metrics context
4. The `logs` command works for ANY systemd unit — not limited to predefined services
5. `k8s-node-debug` skill is deprecated — use `ssh-debug-k8s-worker` instead

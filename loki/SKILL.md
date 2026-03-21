---
name: loki
description: Query Loki logs via logcli. Use when user says check logs, search logs, show logs, query loki, logql, logcli, pod logs, systemd logs, journal logs, container logs, what happened on host, log search, log history, error logs, recent errors, grep logs, tail logs, overseer logs, investigate logs, service logs, failed service, application logs, log labels, log volume.
allowed-tools:
  - Bash(logcli:*)
---

# Loki Log Query Skill

All queries use `logcli` directly. Always pass `--addr`; pass `--org-id` for multi-tenant instances (omit for single-tenant like Ceph).

## Instances

| Alias | URL | org-id | Context |
|---|---|---|---|
| **hel-infra** (default) | `http://172.20.7.228:80` | `fake` | hel-infra-prod, VM systemd + k8s logs |
| hel-services | `http://172.20.66.204:80` | `fake` | hel-services-prod |
| dxb-services-staging | `http://172.18.163.57:80` | `fake` | dxb-services-staging |
| ceph | `http://10.16.222.26:3100` | _(none — omit --org-id)_ | Ceph storage cluster |

To find Loki in other clusters: `kubectl --context <ctx> get svc -n loki loki-gateway -o jsonpath='{.spec.clusterIP}'`

## Usage

```bash
# Query logs (default: hel-infra)
logcli --addr http://172.20.7.228:80 --org-id=fake query '{unit="overseer.service"}' --since 1h --limit 100

# Query a different instance
logcli --addr http://172.20.66.204:80 --org-id=fake query '{namespace="crypto-prod", container="app"}' --since 30m --limit 200

# Ceph (no org-id)
logcli --addr http://10.16.222.26:3100 query '{job="ceph"}' --since 1h --limit 100

# Time range (absolute)
logcli --addr http://172.20.7.228:80 --org-id=fake query '{host="srv013"}' --from="2026-03-10T08:00:00Z" --to="2026-03-10T09:00:00Z" --limit 500

# Forward (chronological order)
logcli --addr http://172.20.7.228:80 --org-id=fake query '{unit="vault.service"}' --since 2h --limit 200 --forward

# Quiet mode (suppress metadata header, keep timestamps + labels)
logcli --addr http://172.20.7.228:80 --org-id=fake query '{host="srv013"}' --since 1h --limit 50 --quiet

# Raw mode (log lines only, no labels/timestamps/metadata)
logcli --addr http://172.20.7.228:80 --org-id=fake query '{host="srv013"}' --since 1h --limit 50 -o raw --quiet
```

## LogQL Patterns

### Label Matchers
```logql
{unit="overseer.service"}                          # exact match
{namespace="monitoring", container="prometheus"}    # multiple labels
{host=~"roach-.*"}                                 # regex match
{unit!="cron.service"}                             # not equal
{namespace=~"crypto-.*|steno-.*"}                  # regex OR
```

### Line Filters
```logql
{unit="overseer.service"} |= "error"              # contains (case-sensitive)
{unit="overseer.service"} |~ "(?i)error"           # contains (case-insensitive)
{unit="overseer.service"} != "debug"               # does not contain
{unit="overseer.service"} !~ "health|readiness"    # exclude regex
{host="srv013"} |= "OOM"                          # search for OOM
```

### Parsing + Filtering
```logql
# JSON logs: extract and filter on parsed fields
{namespace="crypto-prod"} | json | level="error"
{namespace="crypto-prod"} | json | latency_ms > 1000

# Logfmt logs
{unit="overseer.service"} | logfmt | level="error"

# Pattern: extract from unstructured logs
{unit="nginx.service"} | pattern `<ip> - - <_> "<method> <path> <_>" <status> <size>` | status >= 500

# Line format: reformat output
{namespace="monitoring"} | json | line_format "{{.level}} {{.msg}}"
```

## Discovery

```bash
# List all label names
logcli --addr http://172.20.7.228:80 --org-id=fake labels

# List values for a label
logcli --addr http://172.20.7.228:80 --org-id=fake labels host
logcli --addr http://172.20.7.228:80 --org-id=fake labels unit
logcli --addr http://172.20.7.228:80 --org-id=fake labels namespace

# List label combinations (series)
logcli --addr http://172.20.7.228:80 --org-id=fake series '{host="srv013"}'

# Volume (which streams have most logs, default 30 series — use --limit for more)
logcli --addr http://172.20.7.228:80 --org-id=fake volume '{host=~".+"}' --since 1h --limit 100
```

## Large Queries

For queries spanning >1h or high-volume streams, use parallel flags to avoid timeouts. Note: `--limit` is ignored when parallel workers > 1.

```bash
logcli --addr http://172.20.7.228:80 --org-id=fake query '{unit="overseer.service"}' --since 24h --parallel-duration 15m --parallel-max-workers 4
```

## Tips

1. **Always set --limit** — default is only 30 lines. Use 100-500 for investigation, 1000+ for bulk export
2. **--forward** for chronological order — default is newest-first (reverse)
3. **--quiet** suppresses metadata header (common labels, API URL). Use `-o raw --quiet` for log lines only (no labels/timestamps)
4. **Network is routable** — no port-forward needed. If queries timeout, check `allow-anton` NetworkPolicy in the loki namespace
5. **VM logs** use `unit` and `host` labels (systemd journal). **K8s logs** use `namespace`, `pod`, `container` labels
6. **--since** accepts Go durations: `30m`, `1h`, `24h`. No `d` unit — use `168h` for 7 days
7. **Combine line filters** for precision: `{unit="app.service"} |= "error" != "expected_error"`

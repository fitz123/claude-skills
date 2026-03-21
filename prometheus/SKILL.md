---
name: prometheus
description: Query Prometheus metrics via API. Use when user says check metrics, query metrics, look at metrics, show me metrics, get metric, error rate, latency, request rate, scrape targets, alerts firing, alert status, prometheus query, promql, check monitoring, what's the rate of, how many requests, is service up (up metric), SLO, SLI, metric trend, metric history, rate of errors, query range, label values, what metrics exist. Supports instant and range queries across all clusters.
allowed-tools:
  - Bash(/Users/ninja/.claude/skills/prometheus/prom:*)
---

# Prometheus Query Skill

All queries go through the `prom` wrapper which outputs AI-optimized JSON. Never use raw curl or pipes.

## Instances

| Alias | URL | Context |
|---|---|---|
| **hel-infra-external** (default) | `http://172.20.13.197:9090` | hel-infra-prod, external targets |
| hel-infra-k8s | `http://172.20.8.224:9090` | hel-infra-prod, k8s internals |
| services-prod-k8s | `http://172.20.74.242:9090` | hel-services-prod, k8s internals |
| services-prod-external | `http://172.20.77.114:9090` | hel-services-prod, external targets |
| dxb-infra-external | `http://172.19.33.229:9090` | dxb-infra-prod, external targets |
| dxb-infra-k8s | `http://172.19.38.62:9090` | dxb-infra-prod, k8s internals |
| dxb-staging-k8s | `http://172.19.11.28:9090` | dxb-infra-staging, k8s internals |
| dxb-staging-external | `http://172.19.4.126:9090` | dxb-infra-staging, external targets |
| hel-services-staging-k8s | `http://172.20.110.140:9090` | hel-services-staging, k8s internals |
| dxb-services-staging-k8s | `http://172.18.186.237:9090` | dxb-services-staging, k8s internals |
| ceph | `http://10.16.222.26:9095` | Ceph storage cluster (standalone) |

## Usage

Always use the full script path. Never set shell variables or use pipes.

```bash
# Instant query (default: hel-infra-external)
/Users/ninja/.claude/skills/prometheus/prom 'up{job="vector"}'

# Query a different instance with --url
/Users/ninja/.claude/skills/prometheus/prom --url http://172.20.74.242:9090 'up'

# Query ceph
/Users/ninja/.claude/skills/prometheus/prom --url http://10.16.222.26:9095 'ceph_osd_apply_latency_ms'

# Query from file (avoids shell metacharacter permission prompts)
/Users/ninja/.claude/skills/prometheus/prom -f /tmp/prom-query.txt
/Users/ninja/.claude/skills/prometheus/prom -f /tmp/prom-query.txt -r 24h --url http://172.20.74.242:9090

# Range query (last 24h)
/Users/ninja/.claude/skills/prometheus/prom 'rate(node_cpu_seconds_total[5m])' -r 24h

# Range with custom step (use larger step for >24h ranges)
/Users/ninja/.claude/skills/prometheus/prom 'up' -r 7d -s 1h

# Discovery
/Users/ninja/.claude/skills/prometheus/prom --metrics              # List all metrics
/Users/ninja/.claude/skills/prometheus/prom --metrics "node_"      # Filter by pattern
/Users/ninja/.claude/skills/prometheus/prom --values job            # List job label values
/Users/ninja/.claude/skills/prometheus/prom --labels up             # List labels for metric
```

## Output Format (JSON)

Instant query:
```json
{"type": "vector", "count": N, "data": [{"labels": {...}, "value": 123.45}]}
```

Range query:
```json
{"type": "matrix", "count": N, "data": [{"labels": {...}, "min": 1, "max": 10, "avg": 5, "samples": 288, "values": [["2026-03-01T00:00:00", 5.2], ...]}]}
```

## PromQL Patterns

```promql
rate(metric_total[5m])              # Rate of counter
sum by (host) (rate(...))           # Sum by label
{host=~".*roach.*"}                 # Filter by regex
rate(...) > 0                       # Non-zero only
```

## Tips

1. Use `rate()` for `_total` metrics — they're counters
2. Network is routable — no port-forward needed
3. Match instance to target: k8s pods -> k8s instance, VMs/network -> external instance
4. For ranges >24h, use a larger step (`-s 1h` or `-s 6h`) to reduce data volume
5. The script has a 30s curl timeout built in
6. Errors return structured JSON — no tracebacks
7. **AI agents**: Use `-f /tmp/prom-query-XXXXX.txt` with unique filename (write query with Write tool first) to avoid shell metacharacter permission prompts

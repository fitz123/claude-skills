---
name: teamcity
description: Manage TeamCity CI/CD projects, builds, and agents. Use when checking build status, listing configurations, viewing build steps, triggering builds, or investigating failures.
allowed-tools:
  - Bash(/Users/ninja/.claude/skills/teamcity/tc:*)
---

# TeamCity Skill

All queries go through the `tc` wrapper which handles auth via macOS Keychain and outputs AI-optimized JSON. Never use raw curl.

**Server**: `https://teamcity-hel.ordercapital.com`
**Web UI**: Same URL, append paths from `webUrl` fields in responses.

## Commands

### Browse

```bash
# List all projects
/Users/ninja/.claude/skills/teamcity/tc projects

# Project details (build types, subprojects, parameters)
/Users/ninja/.claude/skills/teamcity/tc project Infrastructure

# List build configurations in a project
/Users/ninja/.claude/skills/teamcity/tc buildtypes Infrastructure

# Build config details (templates, VCS roots, parameters)
/Users/ninja/.claude/skills/teamcity/tc buildtype Infrastructure_AptInfraCommon

# Build steps (with truncated script bodies)
/Users/ninja/.claude/skills/teamcity/tc steps Infrastructure_AptInfraCommon

# Build parameters (passwords masked)
/Users/ninja/.claude/skills/teamcity/tc params Infrastructure_AptInfraCommon
```

### Builds

```bash
# Recent builds (default 10)
/Users/ninja/.claude/skills/teamcity/tc builds Infrastructure_AptInfraCommon

# More builds
/Users/ninja/.claude/skills/teamcity/tc builds Infrastructure_AptInfraCommon --count 30

# Single build details
/Users/ninja/.claude/skills/teamcity/tc build 12345

# Build statistics (durations, test counts)
/Users/ninja/.claude/skills/teamcity/tc stats 12345
```

### Investigate Failures

```bash
# Build log (last 200 lines)
/Users/ninja/.claude/skills/teamcity/tc log 12345

# Build problems
/Users/ninja/.claude/skills/teamcity/tc problems 12345

# Failed tests
/Users/ninja/.claude/skills/teamcity/tc tests 12345
```

### Agents & Queue

```bash
# List all agents (connected/enabled/authorized status)
/Users/ninja/.claude/skills/teamcity/tc agents

# Build queue
/Users/ninja/.claude/skills/teamcity/tc queue
```

### Actions (WRITE)

```bash
# Trigger a build
/Users/ninja/.claude/skills/teamcity/tc trigger Infrastructure_AptInfraCommon

# Trigger on a specific branch
/Users/ninja/.claude/skills/teamcity/tc trigger Infrastructure_WireguardGo --branch refs/heads/main

# Cancel a running build
/Users/ninja/.claude/skills/teamcity/tc cancel 12345
```

### Raw API Access

```bash
# GET any endpoint (auto-prefixes /app/rest/ if path doesn't start with /)
/Users/ninja/.claude/skills/teamcity/tc get "projects/id:Infrastructure/buildTypes"

# Full path
/Users/ninja/.claude/skills/teamcity/tc get "/app/rest/agents?locator=connected:true"
```

## Investigation Workflow

When debugging a failed build:
1. `tc builds <buildtype-id>` — find the failed build ID
2. `tc build <id>` — get status, statusText, agent, trigger info
3. `tc problems <id>` — check build problems
4. `tc tests <id>` — check failed tests
5. `tc log <id>` — read build log (last 200 lines)

## Known Project Structure

```
Infrastructure (root)
├── apt-infra-common
├── deb-s3
├── wireguard-go/
├── bandstat-exporter/
├── filestat-exporter/
├── linux-kernel-rt/
├── Go Projects/
├── ceph-csi-cephfs/
├── devops-build-images/
├── dns/
└── octopusdeploy-helm/
```

## Tips

1. Build type IDs follow pattern: `ProjectId_SubName` (e.g., `Infrastructure_WireguardGo`)
2. The script has 30s request timeout and 5s connect timeout
3. Password parameters are automatically masked in output
4. Long step properties (scripts) are truncated to 500 chars
5. Token is retrieved from macOS Keychain on each call — no env vars needed

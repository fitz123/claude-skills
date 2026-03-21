# Ralphex Architectural Decisions

Why our Minime adaptation differs from the original umputun/ralphex.

## Original vs Our Stack

| Aspect | Original (umputun/ralphex) | Ours (Minime skill) |
|--------|---------------------------|----------------------|
| Runtime | Go CLI binary | SKILL.md interpreted by Minime agent |
| Agent spawn | Claude Code `Task` tool (foreground parallel) | `sessions_spawn` (async, file-based coordination) |
| Models | Single Claude model for all agents | Multi-model: Opus (creator), Sonnet (fixer/reviewers), Codex (quality) |
| External review | Codex CLI (Phase 3, separate binary) | Quality reviewer on different model family (Codex) |
| Signals | `<<<RALPHEX:REVIEW_DONE>>>` / `<<<RALPHEX:TASK_FAILED>>>` | `.done` file markers + auto-announce |
| Config | YAML config + Go structs | Template variables in SKILL.md |
| Agents | 5 fixed: quality, implementation, testing, simplification, documentation | 5 core + 2 optional: security, architecture, simplification, quality, implementation + testing, documentation |
| Plan creation | Interactive (QUESTION signal → user input → iterate) | Separate `plan` skill handles this |
| Task execution | Phase 1: iterative (one task section per loop) | Creator writes everything in one pass |

## Key Design Decisions

### 1. File-Based Coordination (not foreground parallel)

**Original:** Uses Claude Code's `Task` tool — all 5 agents run as foreground parallel tasks in the same message. Results are collected synchronously. Simple, reliable.

**Why we can't:** Minime's `sessions_spawn` is async. No foreground parallel execution. Sub-agents run independently and report back via auto-announce.

**Our solution:** Each sub-agent writes results to `{{RALPHEX_TMPDIR}}/review-iter-N-ROLE.md` + `.done` marker. Shell watcher polls for `.done` files. Fallback: 60s extra wait → mark missing as unavailable → quorum check.

**Trade-off:** More complex, but necessary for Minime. The `.done` marker pattern is battle-tested across 3 dogfooding iterations.

### 2. Multi-Model Instead of Single Claude

**Original:** All agents use the same Claude model. Model diversity comes from Phase 3 (Codex CLI — a completely different system).

**Our choice:** Different models per role:
- **Opus** for creator (needs depth for from-scratch generation)
- **Sonnet** for fixer + most reviewers (fast, targeted editing)
- **Codex** for quality reviewer (different model family = different blind spots)

**Why:** We don't have Codex CLI (it's a Go binary wrapping OpenAI API). Instead, we use Codex as a reviewer model directly via sessions_spawn. This gives us cross-model validation without a separate external tool.

### 3. Security Reviewer (not in original)

**Original:** Security is part of `quality.txt` — the quality agent handles bugs + security + simplification (all in one).

**Our choice:** Security is a dedicated core reviewer with its own KB (TOOLS.md credential rules, AGENTS.md Protected Files).

**Why:** Minime agents have real filesystem access (read/write/exec). Security concerns are more acute than in a typical code review. A dedicated reviewer catches injection, path traversal, credential exposure that a combined quality agent might deprioritize.

### 4. Architecture Reviewer (not in original)

**Original:** No dedicated architecture reviewer. Structural concerns are split across quality (logic) and implementation (wiring).

**Our choice:** Architecture is a dedicated core reviewer checking structural correctness, integration, API contracts, separation of concerns.

**Why:** Our primary use case is Minime skills and workspace files — structural correctness matters more than in typical code review.

### 5. No Phase 3 (External Codex CLI)

**Original:** Phase 3 runs Codex CLI (or custom script) as an independent external reviewer. Completely separate system, zero shared context. Iterates until clean.

**Our equivalent:** Quality reviewer on Codex model provides cross-model validation. Not a separate phase — it's one reviewer in the same loop.

**Trade-off:** Less isolation (same prompt structure, same TMPDIR). But practical — we can't run external CLI tools as review systems. The model diversity (Codex vs Sonnet) still catches different blind spots.

### 6. Single Loop Instead of Two-Phase Review

**Original:** Phase 2 (5 agents, comprehensive) → Phase 4 (2 agents — quality + implementation, critical/major only). Structurally separate.

**Our choice:** Single loop, MAX_ITERATIONS iterations. Final iteration appends "CRITICAL/MAJOR only" filter.

**Why:** Simpler. The two-phase structure is an optimization — run fewer reviewers on the final pass. Our approach runs all reviewers every time but filters severity on the last iteration. Slightly more expensive, functionally equivalent.

### 7. Reviewer Mandates are Specialized (not Combined)

**Original quality.txt:** Handles correctness + security + simplification (37 lines, three sections).

**Our approach:** Three separate specialists — Quality (correctness only), Security (dedicated), Simplification (dedicated). Each has a focused mandate and explicit "Do NOT review: [other domains]" instruction.

**Why:** Prevents mandate bleed. A combined agent tends to weight one domain over others. Separate specialists with explicit boundaries produce more thorough, focused reviews.

### 8. Plan Creation is a Separate Skill

**Original:** `make_plan.txt` — interactive plan creation with QUESTION signals, draft review, user approval. Built into Ralphex.

**Our approach:** Plan creation lives in `skills/plan/SKILL.md`. Ralphex focuses on review pipeline only.

**Why:** Separation of concerns. Plan skill handles interactive Q&A, exploration, cross-validation. Ralphex handles review/fix iteration. They compose: plan skill can spawn Ralphex for review, Ralphex can use a plan as input.

### 9. Task Execution is One-Shot (not Iterative)

**Original:** `task.txt` — processes one task section per iteration, checks off checkboxes, commits per-task.

**Our approach:** Creator (Opus) writes everything in one pass. No per-task iteration.

**Why:** Our use case is primarily skill files and documentation — typically one file, written holistically. The per-task iteration model suits multi-file code projects with sequential dependencies. For our use case, one-shot is simpler and produces more coherent output.

### 10. Injection Boundaries (not in original)

**Original:** No explicit injection boundaries. Assumes trusted input (Claude Code runs locally on developer's machine).

**Our addition:** Reviewer prompts have INJECTION BOUNDARY warning. Fixer prompt treats reviewer output as UNTRUSTED DATA. KB paths are boundary-checked. OUTPUT_FILES are repo-root restricted.

**Why:** Minime agents operate in a more complex environment — files under review may contain adversarial content, KB paths could be manipulated, and the pipeline runs autonomously. Defensive boundaries are necessary.

### 11. Timeout Chain & Watcher Design

**Problem:** Async sub-agents can fail in multiple ways — silent spawn failure (never starts), hang (starts but never finishes), or crash (killed by platform). Each needs detection.

**Our solution: four-layer timeout chain:**

```
0s     — spawn reviewer
30s    — Spawn Health Check: sessions_history(limit=1, includeTools=true)
         → 0 messages = silent failure → respawn once
         → ≥1 message = agent alive → proceed to watcher
480s   — Platform kills agent (runTimeoutSeconds)
540s   — Bash DEADLINE (watcher exits, reports missing .done files)
600s   — exec timeout (kills bash if it hangs)
610s   — yieldMs (guarantees exec returns inline, never backgrounds)
+60s   — Fallback recheck of .done files
         → still missing → Respawn Gate: can quorum be saved?
           → yes → respawn missing (1 retry), second watcher (540s)
           → no → mark unavailable → ABORT via quorum check
```

**Key design: watcher is a dumb file poller.** It doesn't know or care if agents are alive. Between 30s (health check) and 540s (DEADLINE) is a blind zone — by design. Checking `sessions_history` every 15s would be expensive (tool calls = tokens = context). Since platform kills hung agents at 480s, the blind zone costs at most 60s of wasted wait.

**Why yieldMs ≥ timeout:** If `yieldMs < timeout`, `exec` backgrounds the process and orchestrator must use `process(action=poll)` to get results. `process poll` can hang indefinitely (discovered in dogfooding v3). Setting `yieldMs=610000 > timeout=600` ensures exec always returns inline.

**Why `.done` marker files:** Race condition prevention. Watcher might read `.md` file before content is fully flushed. `.done` is written AFTER the review file, guaranteeing content completeness.

**Why two detection mechanisms:**
- **Spawn Health Check** (30s) catches silent spawn failures — `sessions_spawn` accepted but agent never started
- **Watcher timeout** (540s) catches hangs and crashes — agent started but never produced output
- **Respawn** (post-watcher) recovers from transient failures (rate limits, provider lag)

These are complementary: health check is cheap and fast (catches 90% of failures early), watcher is the safety net.

---

### 12. Respawn Strategy

**Problem:** Timed-out reviewers are marked `unavailable`. If enough time out, pipeline ABORTs even though the failure may be transient.

**Our solution: single retry with respawn gate.**

1. After watcher timeout, count missing reviewers
2. **Respawn gate:** if `missing >= EXPECTED - MIN_REVIEWERS + 1` → quorum unreachable even with perfect retries → ABORT immediately (don't waste time)
3. Otherwise → respawn each missing reviewer (1 retry, same params)
4. Second watcher with `-retry` suffix files → same DEADLINE
5. Still missing after retry → `unavailable` (final)

**Why only 1 retry:** Transient failures (rate limit, provider lag) resolve on retry. Persistent failures (model down, task too complex) won't. Retrying more than once wastes time for no gain.

**Why respawn gate:** If 4/5 reviewers timed out, provider is likely down. Respawning all 4 just to fail again wastes 540s. Gate prevents this.

### 13. Orchestrator Model: Codex, not Sonnet

**Discovered in:** dogfooding v3 + v4 (multiple incidents)

**Problem:** Sonnet repeatedly ignored the PIPELINE-WIDE RULE "NEVER use `process(action=poll)`" and fell back to polling after fixer spawn. This caused the orchestrator to hang indefinitely. The rule was stated clearly in SKILL.md but Sonnet's default behavior (wait for auto-announce via poll) overrode the written instruction.

**Root cause:** Sonnet received a Minime system message "1 active subagent, wait for remaining results" after fixer spawn. Its natural response to this context is `process(action=poll)`. A written rule in a long SKILL.md is not strong enough to override this instinct.

**Fix:** Switch orchestrator to Codex. In the same scenario, Codex immediately constructed an `exec`-based file watcher without any prompting — following the SKILL.md instruction correctly.

**Why Codex for orchestrator:**
- Follows long-form procedural instructions more precisely
- Does not override written rules with model instincts
- Less likely to take "helpful shortcuts" that violate pipeline constraints

**Trade-off:** Codex is a different model family — may have less common sense for edge cases. But for an orchestrator, instruction-following > creative problem-solving.

---

## What We Intentionally Don't Have

1. **Finalize step (squash/rebase)** — Implemented in Phase 5. Best-effort squash of pipeline commits on success.
2. **Progress file** — Reviewers don't see iteration history. Mitigated by fixer's CONFIRMED/FALSE POSITIVE verification.
3. **Git diff context** — Reviewers read full files, not diffs. Noisier but catches more pre-existing issues.
4. **Custom eval/review prompts** — No `custom_eval.txt` / `custom_review.txt` equivalent. Presets cover our use cases.

---

*Created: 2026-02-28. Updated after 3 comparison rounds with original.*

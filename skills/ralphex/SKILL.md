---
name: ralphex
description: "Multi-agent iterative review pipeline via Go binary (umputun/ralphex). Create → review → fix → re-review. Use for code, skills, scripts, docs that need quality assurance."
user-invocable: false
---

# Ralphex — Iterative Review Pipeline

Go-based orchestrator by umputun. Hardcoded phase transitions (not LLM-driven).
Flow: **Task → Claude Review → Fix → Codex Review → Fix → Re-review → Finalize**

## Installation

```bash
brew install umputun/apps/ralphex
```

Auto-updates via brew. Never build from source.

## Documentation & Source

- **Docs:** <https://github.com/umputun/ralphex>
- **Local clone (reference):** `/tmp/ralphex/` — useful for checking prompts/config structure
- **Default prompts:** `/tmp/ralphex/pkg/config/defaults/prompts/`
- **Default agents:** `/tmp/ralphex/pkg/config/defaults/agents/`
- **Go orchestrator code:** `/tmp/ralphex/pkg/processor/runner.go`

## Config Locations

**⚠️ НЕ использовать `--config-dir`.** Ralphex auto-detect'ит `.ralphex/` в cwd как local config, а `~/.config/ralphex/` как global. При явном `--config-dir .ralphex` notify_channels ломается (баг: umputun/ralphex#214).

- **Our config:** `.ralphex/` (в workspace) — local override, auto-detected
- **Progress logs:** `.ralphex/progress/` (auto-created, gitignored)

## Our Agent Set (7)

Local agents in `.ralphex/agents/`:
| Agent | Source | Purpose |
|-------|--------|---------|
| quality | default | Bugs, correctness, error handling |
| simplification | default | Over-engineering detection |
| implementation | default | Requirement coverage, completeness |
| documentation | default | README/docs gaps |
| testing | default | Test coverage and quality |
| security | **custom** | Vulnerabilities, credential exposure, injection |
| architecture | **custom** | Structure, integration, design decisions |

## Per-Agent Model Override

Each agent file supports YAML frontmatter for model selection:

```
---
model: opus
---
Review code for security vulnerabilities...
```

Valid models: `haiku`, `sonnet`, `opus`.
Without frontmatter → uses global model from `claude_args --model`.

### Model levels (precedence):
1. **Agent frontmatter** (`model: opus` in agent .txt file) — per-reviewer
2. **Global claude_args** (`--model sonnet` in config) — task/fix/review default
3. **Codex config** (`codex_model`, `codex_reasoning_effort`) — external review

## Repository Selection (ОБЯЗАТЕЛЬНО)

**Bot code** (`bot/src/`) → run from **public repo** (`/Users/ninja/src/claude-code-bot/`). Changes go through PR to `fitz123/claude-code-bot`.
**Workspace code** (skills, rules, scripts, config) → run from **workspace** (`/Users/ninja/.minime/workspace/`).

Rule: его задачи — из его репы, наши — из нашей.

## ⚠️ Pre-Launch Checklist (ОБЯЗАТЕЛЬНО)

**Before EVERY `ralphex` run, do these checks:**

### 0. Worktree — чистая? (БЛОКЕР)
Ralphex работает в **изолированном git worktree** (`.ralphex/worktrees/<branch>`). Основная рабочая директория остаётся на main — параллельные сессии не затрагиваются. Грязный worktree = instant fail.

```bash
cd /Users/ninja/.minime/workspace
git status --short 2>&1
```

- **Чисто** (пустой вывод) → продолжай
- **Есть изменения** → зафиксируй перед запуском:
  - Релевантные к задаче → `git add -A && git commit -m "wip: <context>"`
  - Артефакты/кэши (submodule `__pycache__`, `.pyc`, etc.) → удалить мусор, закоммитить
  - **Submodules** с untracked content → зайти внутрь, preview `git clean -nd`, confirm, then `git clean -fd`, вернуться
- **НЕ ЗАПУСКАТЬ** Ralphex пока `git status --short` не вернёт пустой вывод

### 1. Model — какая модель?
- **Sonnet** (default) — review, skills, docs, non-critical code
- **Opus** — critical infrastructure, AGENTS.md/SOUL.md level changes
- Set via: `claude_args = ... --model sonnet` in config

### 2. Iterations — сколько итераций?
- **3** (default) — enough for most tasks (task + review + fix)
- **5** — complex multi-file changes
- **10** — only for critical rewrites (rare)
- Set via: `max_iterations = 3` in config

### 3. Codex review — нужен?
- **Yes** (default) — second opinion from different model
- **No** — simple/fast tasks, save tokens
- Set via: `codex_enabled = true/false` in config

### 4. Codex reasoning effort
- **high** (default) — balanced
- **xhigh** — critical code only
- Set via: `codex_reasoning_effort = high` in config

### Defaults (current global config):
```
model = sonnet
max_iterations = 10
codex_enabled = true
codex_model = gpt-5.3-codex
codex_reasoning_effort = high
```

## Usage

### 1. Write a plan file

```markdown
# Plan: <what to do>

## Goal
<clear description>

## Context
<relevant files, previous work, constraints>

## Validation Commands
\```bash
<commands to verify the work>
\```

## Tasks

### Task 1: <name>
- [ ] Step one
- [ ] Step two
- [ ] Step three
```

Put in `reference/plans/<name>.md`.

### 2. Run

⚠️ **Ralphex может работать часами.** Итерации контролируют завершение, не timeout.

⚠️ **CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000** — ОБЯЗАТЕЛЬНО. Без этого Claude Code может упасть с "API Error: exceeded 32000 output token maximum", и Ralphex трактует это как fatal error и останавливает весь run.

**Запуск через nohup (из Claude Code CLI сессии):**

1. Перейти в workspace, над которым будет работать ralphex
2. Запустить через `nohup` в фоне с перенаправлением в `/tmp/ralphex-<plan-name>.log`

```bash
cd <workspace-dir> && \
CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000 \
nohup ralphex --debug --no-color \
  .ralphex/plans/<plan-name>.md \
  > /tmp/ralphex-<plan-name>.log 2>&1 &
```

Пример:
```bash
cd ~/.minime/bot && \
CLAUDE_CODE_MAX_OUTPUT_TOKENS=64000 \
nohup ralphex --debug --no-color \
  .ralphex/plans/bot-fixes-round1.md \
  > /tmp/ralphex-bot-fixes-round1.log 2>&1 &
```

Процесс отвязывается от сессии — можно продолжать работать. Нотификация придёт в Telegram по завершении (настроена через `notify_custom_script` в конфиге).

### Post-Launch Verification (обязательно)

После запуска **обязательно** убедиться что ralphex реально работает, а не упал сразу:

```bash
sleep 5 && tail -10 <log-file>
```

Считать запущенным **только** когда в логе видно `task iteration 1` или активную работу над первой задачей. Если в логе `error:` — значит упал, разобраться и перезапустить.

Никогда не говорить пользователю "запущен" до этой проверки.

Options:
- `--debug` — verbose logging
- `-r` / `--review` — skip task, run review only
- `-e` / `--external-only` — skip task + first review, codex only
- `-t` / `--tasks-only` — skip all reviews
- `--max-iterations N` — override config
- `--skip-finalize` — skip git rebase/squash step
- `--serve` — web dashboard at localhost:8080

### 3. Monitor

Для run с форматом `RUN_ID` (см. выше):
```bash
# список последних ранов
ls -lt /tmp | rg '^d.*ralphex-run-' | head

# читать лог конкретного run
RUN_ID=<run-id>
tail -f /tmp/ralphex-run-${RUN_ID}/ralphex.log

# проверить метаданные и код выхода
cat /tmp/ralphex-run-${RUN_ID}/run.meta
cat /tmp/ralphex-run-${RUN_ID}/exit.code
```

Примечание:
- `--no-color` в запуске делает лог стабильнее для парсинга скриптами.

## Typical Presets

### Quick review (skill/doc changes)
```
model = sonnet, iterations = 3, codex = off
```

### Standard (code changes)
```
model = sonnet, iterations = 3, codex = on, reasoning = high
```

### Critical (infra, config, core files)
```
model = opus, iterations = 5, codex = on, reasoning = xhigh
```

## Notifications

Ralphex → Telegram при complete/error.

- Config: `notify_channels = custom`, `notify_custom_script = /Users/ninja/.minime/workspace/.ralphex/scripts/notify-minime.sh`
- Script: `.ralphex/scripts/notify-minime.sh` — получает Result JSON на stdin, парсит, шлёт через `deliver.sh`
- Канал: Minime HQ, Ops topic (chat `-1003894624477`, thread `591`)
- Result JSON также сохраняется в `/tmp/ralphex-last-result.json`
- **⚠️ НЕ использовать `--config-dir`** — ломает нотификации (umputun/ralphex#214)

## Lessons Learned

- **LLM orchestrators NEVER reliably launch fixer** — 3 models (Codex ×2, Opus ×1) all failed. That's why we use the Go orchestrator.
- **Local `.ralphex/agents/` replaces all defaults** — must copy defaults + add custom agents.
- **Plan file quality = run quality** — vague plans produce vague results. Be specific.
- **Progress survives interrupts** — kill and re-run, ralphex picks up from unchecked tasks.
- **architectural-decisions.md** — point architecture reviewer to it to reduce false positives.
- **НИКОГДА не запускать параллельные Ralphex раны в одном git worktree.** Они коммитят в одну ветку → review видит чужие изменения → бесконечный цикл. Параллельные модули → отдельные ветки или последовательный запуск. (Урок 2026-03-01: Avito + Cian в одной ветке → Avito review зациклился на 80+ мин.)
- **`--config-dir .ralphex` ломает нотификации** — ralphex auto-detect'ит `.ralphex/` в cwd. Явный флаг вызывает баг, при котором notify_channels молча игнорируются. (umputun/ralphex#214, обнаружено 2026-03-15)

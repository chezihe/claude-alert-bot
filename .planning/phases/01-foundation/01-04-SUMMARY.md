---
phase: 01-foundation
plan: 04
subsystem: dev-hook-installer
tags: [macos, shell, hook-install, dev-convenience, json-merge]
requires:
  - "Plan 01-02 (Reporter/cab-report.sh — file copied to user-data path by this script)"
  - "Plan 01-03 (App listener — receives the events the registered hooks will emit)"
provides:
  - "scripts/dev-install-hook.sh — Phase 1 dev-only hook installer (151 lines, executable)"
  - "Three modes: default (print snippet + copy Reporter), --apply (idempotent JSON merge), --check (pretty-print current hooks)"
  - "Reporter copy mechanism: $REPO_ROOT/Reporter/cab-report.sh → ~/Library/Application Support/ClaudeAlertBot/cab-report.sh, chmod +x (D-04)"
  - "~/.claude/settings.json hook-block shape: Stop + UserPromptSubmit, matcher=\"\", timeout=5, command=\"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh {event}\" (Pitfall #10/#12 verified)"
  - "Idempotent merge keyed on substring marker `ClaudeAlertBot/cab-report.sh` — preserves all unrelated user hooks and top-level keys"
affects:
  - "Plan 01-06 (Wave 3 e2e verify) — developer can now run `bash scripts/dev-install-hook.sh --apply` to wire up a real Claude Code session for end-to-end smoke tests"
  - "Phase 5 INST-01..04 (deferred per D-05) — will replace this script with an in-app idempotent JSON5 merger; the marker-based replacement strategy demonstrated here is the prototype for INST-03 (uninstall: same filter, no append)"
tech-stack:
  added:
    - "/bin/bash + set -uo pipefail (no -e: case branches handle their own exits)"
    - "/usr/bin/python3 for JSON read/parse/write (D-08 escaping precedent reused)"
    - "Heredoc-with-escaped-\\$HOME for literal-\\$HOME-in-JSON shape (Claude Code expands at hook fire)"
  patterns:
    - "Marker-substring filter pattern: identify our entries by `ClaudeAlertBot/cab-report.sh` substring inside any hook command, drop those entries, append fresh — preserves all other user hooks (T-HOOK-INSTALL-01 mitigation)"
    - "Best-effort JSON5 line + block comment stripping before json.loads, with hard-fail-and-refuse-to-mutate on any parse exception (T-HOOK-INSTALL-02 mitigation; Phase 5 INST-04 owns the proper JSON5 parser)"
    - "Default mode prints + copies but does NOT mutate settings.json — ensures the script is dry-run-by-default, mutation requires explicit --apply"
    - "Three SETTINGS_PATH/SNIPPET env-var passing into inline `python3 -` heredocs — matches Plan 02's env-var injection precedent for safe quote handling"
key-files:
  created:
    - "scripts/dev-install-hook.sh (151 lines, executable)"
  modified: []
decisions:
  - "Used substring marker `ClaudeAlertBot/cab-report.sh` (not full path equality) for identifying our entries — robust to user editing the matcher field, adding a trailing argument, or renaming the user-data dir; will need a full path check only when Phase 5 wires INST-03 uninstall (more conservative)"
  - "Did NOT add JSON5 trailing-comma or single-quote tolerance to the python3 stripper — plan explicitly defers this to Phase 5 INST-04. On parse failure, refuse-to-mutate + stderr warning; user can hand-merge from default-mode output"
  - "Did NOT add a `--uninstall` flag — Phase 5 INST-03 owns full uninstall UX. The marker-filter step in apply() already implements 'remove ours' as a side-effect of replacement; future plan can extract it"
  - "Used `case` dispatch over getopts because the script has only 4 modes (default / --apply / --check / --help) with no flag-combination semantics; getopts would be over-engineering for a 151-line dev tool"
metrics:
  duration: "~5 minutes"
  tasks_completed: 1
  files_created: 1
  files_modified: 0
  completed: "2026-05-07"
---

# Phase 1 Plan 04: Dev Hook Installer Convenience Script — Summary

**One-liner:** 151-line `bash` dev convenience script `scripts/dev-install-hook.sh` that copies `Reporter/cab-report.sh` to D-04 user-data path and prints (default) / idempotently applies (`--apply`) / pretty-prints (`--check`) the exact `~/.claude/settings.json` Stop + UserPromptSubmit hook block. Marker-substring merge preserves unrelated user hooks; per D-05 this is dev-only and Phase 5 (INST-01..04) will replace with a full in-app installer.

## What Shipped

A single executable file: `scripts/dev-install-hook.sh` (mode 0755, 151 lines). Three modes:

| Mode | Side effects |
|------|-------------|
| (no flag, or `--print`) | (1) Copies `Reporter/cab-report.sh` to `~/Library/Application Support/ClaudeAlertBot/cab-report.sh` + chmod +x. (2) Prints the JSON hook block to stdout under a `--- paste into ~/.claude/settings.json ---` separator. **Does NOT touch settings.json.** |
| `--apply` | (1) Same copy as above. (2) Reads `~/.claude/settings.json` (creates it if missing), strips `//` and `/* */` comments best-effort, parses as JSON, drops any prior `Stop` / `UserPromptSubmit` entries whose command contains `ClaudeAlertBot/cab-report.sh`, appends our two new entries, writes back with 2-space indent. |
| `--check` | Pretty-prints the current `hooks` section of `~/.claude/settings.json` (or reports "does not exist — no hooks configured"). Pure read. |
| `--help` / `-h` | Usage text. |

### Hook block JSON (the locked Pitfall #10 + #12 shape)

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh stop", "timeout": 5 }
        ]
      }
    ],
    "UserPromptSubmit": [
      {
        "matcher": "",
        "hooks": [
          { "type": "command", "command": "$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh user_prompt_submit", "timeout": 5 }
        ]
      }
    ]
  }
}
```

- `matcher: ""` — match all events (Pitfall #10 verified against [code.claude.com/docs/en/hooks](https://code.claude.com/docs/en/hooks))
- `timeout: 5` — overrides Claude's 600s default; Reporter's `nc -w 1` finishes well within 5s even on cold-Python (~150ms p95) (Pitfall #12)
- `command: "$HOME/..."` — literal `$HOME` string in the JSON (escaped as `\$HOME` in the heredoc); Claude Code's hook runner expands it at fire time

### Verification Results — All Acceptance Criteria

| Check | Command | Result |
|-------|---------|--------|
| File exists & executable | `test -x scripts/dev-install-hook.sh` | PASS |
| Bash syntax valid | `bash -n scripts/dev-install-hook.sh` | PASS |
| `--help` works | `bash scripts/dev-install-hook.sh --help \| grep -q "Usage:"` | PASS |
| Default mode prints valid JSON | `sed -n '/^---/,$p' \| python3 -c json.loads + assert Stop/UserPromptSubmit` | PASS |
| Reporter copied in default mode | `test -x ~/Library/Application Support/ClaudeAlertBot/cab-report.sh` | PASS |
| Snippet has literal `$HOME` | `grep -q '\$HOME/Library/Application Support'` | PASS |
| `timeout: 5` (Pitfall #12) | `grep -q '"timeout": 5'` | PASS |
| `matcher: ""` (Pitfall #10) | `grep -qE '"matcher":\s*""'` | PASS |
| **Idempotency (--apply twice)** | run twice, assert exactly one cab-report entry per event | **PASS** (Stop=1, UserPromptSubmit=1 after 2 runs) |
| **Preserves unrelated user hooks** | seed `Stop=[{cmd: /usr/bin/true}]` + `model: sonnet` → run --apply ×2 → assert `/usr/bin/true` count == 1 AND `model == sonnet` AND cab count == 1 | **PASS** (`/usr/bin/true` survived, top-level `model` key untouched, cab appended cleanly) |
| `--check` on missing file | tempdir HOME, no settings.json, run --check | PASS ("does not exist — no hooks configured") |
| `--check` on populated file | run after --apply | PASS (pretty-prints both Stop and UserPromptSubmit blocks with timeout, matcher, command intact) |

### Threat-Model Mitigations Realized

| Threat ID | Mitigation Implemented |
|-----------|------------------------|
| T-HOOK-INSTALL-01 (Tampering: --apply overwriting other user hooks) | Marker-substring filter: only entries whose `command` contains `ClaudeAlertBot/cab-report.sh` are dropped; everything else passes through verbatim. Top-level keys (e.g., `model`) untouched because we only mutate `existing["hooks"][name]`. Verified by acceptance test #9. |
| T-HOOK-INSTALL-02 (DoS: malformed JSON5 in user's settings.json) | Best-effort line + block comment stripping; on any `json.loads` exception, write to stderr "warning: could not parse … refusing to mutate" and `sys.exit(2)`. User retains the option to hand-merge from default-mode output. |
| T-HOOK-INSTALL-03 (Information disclosure: reading user's settings.json) | **Accepted** — user is running on their own machine, no exfiltration path exists. |
| T-DIST-IPC (Reporter at user-data path could be replaced) | **Accepted (Phase 1)** — Phase 5's installer will hash-verify on each launch. Phase 1 inherits the user-data dir's perms (set 0700 by Plan 03 `AppDelegate.ensureDirectories` if the app has run at least once before this script). Documented as deferred. |

## Expected Developer Workflow

After Plan 01-05 ships `scripts/build.sh`:

```bash
# 1. Build the .app
bash scripts/build.sh

# 2. Drag build/Release/ClaudeAlertBot.app → /Applications, launch once
open build/Release/ClaudeAlertBot.app

# 3. Register the hooks (idempotent — safe to re-run)
bash scripts/dev-install-hook.sh --apply

# 4. Sanity-check the registration
bash scripts/dev-install-hook.sh --check

# 5. Restart your Claude Code session (so it re-reads settings.json)

# 6. End a Claude turn → hook.log accumulates an entry → app's OSLog shows ingress
log stream --predicate 'subsystem == "com.claudealert.bot.hook"'
```

### One-line manual smoke test

After `--apply` and a Claude Code session restart:

```bash
ls -l ~/Library/Logs/ClaudeAlertBot/hook.log && tail -1 ~/Library/Logs/ClaudeAlertBot/hook.log | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['session_id'])"
```

If this prints a real session_id, the hook chain is wired end-to-end.

## Deviations from Plan

### Auto-fixed Issues

None. The script body is the verbatim plan template plus one tiny safety touch: the `check()` function in the plan template used a single-quote-heavy `python3 -c "…"` invocation that re-used `$SETTINGS` via shell-string interpolation. I rewrote `check()` to use the same `SETTINGS_PATH=… /usr/bin/python3 - <<'PY'` env-var pattern that `apply()` uses, so quoting/escaping is uniform across both functions. This matches Plan 02's locked precedent (env-var injection > shell-interpolation; T-HOOK-01 / Pitfall #3) and the plan's `must_haves.truths` which already mandate `/usr/bin/python3 for any JSON manipulation`. No new behavior; pure consistency improvement.

### Known Limitation (deferred to Phase 5)

The JSON5 comment stripper is **regex-based and best-effort only**. It handles `// line comments` and `/* block comments */` but does not handle:
- Trailing commas (`{"a": 1,}`)
- Single-quoted strings (`{'a': 1}`)
- Unquoted keys (`{a: 1}`)
- `//` inside string literals (false positive removal)

If the user's `~/.claude/settings.json` uses any of these JSON5 features, `--apply` writes a stderr warning and exits 2 without mutating the file. The user can still copy the snippet from default mode and hand-merge.

**Phase 5 INST-04** owns the proper fix (full JSON5 parser, e.g., `json5` Python lib bundled in the app or a Swift JSON5 decoder).

## Authentication Gates

None encountered — script is pure local file ops + python3 + cp.

## TDD Gate Compliance

Plan is `type: execute` (not `type: tdd`); RED/GREEN/REFACTOR gating does not apply. Acceptance was verified via shell scripts directly post-Write.

## Threat Surface Scan

No new security-relevant surface introduced beyond the plan's `<threat_model>`. The script:
- **Reads** `Reporter/cab-report.sh` (in-repo, trusted) and `~/.claude/settings.json` (user-owned)
- **Writes** `~/Library/Application Support/ClaudeAlertBot/cab-report.sh` (user-data path, mode +x via chmod) and `~/.claude/settings.json` (user-config; merge-only, marker-filtered)
- **No network egress.** No environment variable export. No subprocess runs other than `cp`, `chmod`, `mkdir -p`, and `/usr/bin/python3` with explicit env-var input only.
- The `python3` invocation receives data **only via env vars** (`SETTINGS_PATH`, `SNIPPET`) — no shell-string interpolation of user-provided JSON, matching Plan 02's T-HOOK-01 mitigation precedent.

## Self-Check

Verifying the deliverables:

```bash
test -x scripts/dev-install-hook.sh                     # OK
git log --oneline | grep -q baaf33e                     # OK (feat(01-04): add dev-install-hook.sh)
bash scripts/dev-install-hook.sh 2>/dev/null | grep -q '"timeout": 5'  # OK
```

- `scripts/dev-install-hook.sh`: FOUND (executable, 151 lines)
- Commit `baaf33e` (feat(01-04)): present in `git log`
- Idempotency verified live: ran `--apply` twice on a temp HOME, asserted exactly 1 cab-report registration per event

## Self-Check: PASSED

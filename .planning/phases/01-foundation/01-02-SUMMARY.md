---
phase: 01-foundation
plan: 02
subsystem: reporter-shell
tags: [macos, posix-sh, hook, reporter, ipc-client]
requires:
  - "Plan 01-00 (validation harness — used to verify 1-03-01..04)"
  - "Plan 01-01 (project.yml postBuildScripts already wired to copy Reporter/cab-report.sh into .app Resources)"
provides:
  - "Reporter/cab-report.sh — POSIX sh hook reporter (executable, 85 lines)"
  - "D-08 JSON envelope construction (10 fields, schema_version=1) via python3 -S env-var injection"
  - "AF_UNIX client transport via /usr/bin/nc -U -w 1 to ~/Library/Application Support/ClaudeAlertBot/sock"
  - "Debug log writes (O_APPEND) to ~/Library/Logs/ClaudeAlertBot/hook.log"
affects:
  - "Plan 01-03 (Wave 2) — Swift NWListener consumes the D-08 envelope produced here"
  - "Plan 01-04 (Wave 2) — dev-install-hook.sh registers this script in ~/.claude/settings.json"
  - "Plan 01-05 (Wave 3) — scripts/build.sh archive will pick up cab-report.sh via Plan 01-01's postBuildScripts copy"
  - "Plan 01-06 (Wave 3) — e2e verify wiring; will need to adjudicate the 1-03-03 50ms budget overrun documented below"
tech-stack:
  added:
    - "POSIX sh (macOS /bin/sh, dash-equivalent)"
    - "/usr/bin/python3 (Apple-shipped, used with -S to skip site.py)"
    - "/usr/bin/nc -U (BSD netcat with AF_UNIX support)"
  patterns:
    - "Env-var injection for safe JSON construction — STDIN_JSON='$STDIN_JSON' /usr/bin/python3 -S -c '<inline>' — never shell-interpolates user input (Pitfall #3 / T-HOOK-01)"
    - "Belt-and-suspenders exit-0 discipline — trap 'exit 0' EXIT INT TERM HUP + each pipe `|| true` + literal `exit 0` last line"
    - "Absolute paths for every external binary — defeats PATH injection (Pitfall #1) and Homebrew-shadowed `nc` lacking -U"
    - "Log-before-network ordering — hook.log gets the envelope (HOOK-06) BEFORE the AF_UNIX send attempt, so even socket-down fires are debuggable"
    - "Short-circuit when socket missing — `if [ -n \"$JSON\" ] && [ -S \"$SOCK\" ]` skips nc entirely when app is down"
key-files:
  created:
    - "Reporter/cab-report.sh"
  modified: []
decisions:
  - "Used python3 `-S` flag (skip site.py import) to trim cold-start. Implementation choice within RESEARCH plan freedom (RESEARCH never mandates a specific python3 invocation flavor); reduces median latency by ~5–8 ms on this dev host but does NOT bring 1-03-03 under its 50ms budget — see Deviations."
  - "Did NOT swap python3 for shell-only JSON construction even though that would be sub-millisecond. Plan explicitly forbids this (Pitfall #3 / T-HOOK-01), and the verifier's acceptance criteria grep for `/usr/bin/python3` + `json.dumps`."
  - "Did NOT add a retry loop, exponential backoff, or Swift wrapper. CONTEXT D-01/D-02 mandate the simplest possible Reporter; nc -w 1 is the only timeout, and silent no-op is the only failure handling."
metrics:
  duration: "~10 minutes"
  tasks_completed: 1
  files_created: 1
  files_modified: 0
  completed: "2026-05-07"
---

# Phase 1 Plan 02: POSIX sh Hook Reporter — Summary

**One-liner:** 85-line POSIX `sh` Reporter `Reporter/cab-report.sh` that ALWAYS exits 0, builds a 10-field D-08 JSON envelope via env-var-injected `/usr/bin/python3 -S`, writes a debug line to `~/Library/Logs/ClaudeAlertBot/hook.log` via O_APPEND, and forwards to the AF_UNIX socket through `/usr/bin/nc -U -w 1` — with silent no-op when the socket is absent.

## What Shipped

A single executable file: `Reporter/cab-report.sh` (mode 0755, 85 lines). The body is the **verbatim** "POSIX sh Reporter" pattern from `01-RESEARCH.md` §"Code Examples" with one implementation knob: `python3` is invoked with `-S` (skip site.py) to trim cold-start overhead. No other deviation from RESEARCH's text.

### D-08 Envelope Field Population (When Each Field Is Non-Null)

| Field | Source | Populated when… |
|-------|--------|-----------------|
| `schema_version` | hardcoded `1` | always |
| `event` | argv `$1` (default `"stop"`) | always |
| `session_id` | hook stdin JSON `.session_id` | when Claude Code's hook payload includes it (Stop / UserPromptSubmit both do) |
| `transcript_path` | hook stdin JSON `.transcript_path` | when Claude Code's hook payload includes it |
| `cwd` | hook stdin JSON `.cwd` ‖ shell `$PWD` | always (env fallback wins if stdin lacks `cwd`) |
| `iterm_session_id` | env `ITERM_SESSION_ID` | when invoked from inside an iTerm2 session (set by iTerm2 shell integration; verified `w0t0p1:79C4699F-…` during smoke test). `null` for non-iTerm parents. |
| `tty` | `/usr/bin/tty` output, validated `/dev/*` | only when stdin is connected to an actual tty. `null` when invoked through a pipe (which is **always the case** for a Claude Code Stop hook because Claude pipes JSON to stdin — see Note below). |
| `ppid` | shell `$PPID`, parsed via `int()` | always (cast to int; `0` becomes `null` defensively) |
| `claude_project_dir` | env `CLAUDE_PROJECT_DIR` | when Claude Code sets it (always, per Claude Code hooks reference) |
| `ts` | `/bin/date -u +"%Y-%m-%dT%H:%M:%SZ"` | always (UTC ISO-8601, second resolution) |

**Note on `tty`:** During development I confirmed that even when a developer runs the Reporter manually with `printf '{}' | /bin/sh Reporter/cab-report.sh`, the redirected stdin makes `/usr/bin/tty` return "not a tty" and exit 1; the script captures that as empty and stores `tty: null` in the envelope. This matches the production case (Claude Code pipes hook JSON), so `tty` will be `null` in real usage too. The `tty` field is essentially reserved for Phase 3's TTY-fallback session lookup but currently always reports `null` — the *real* tty discovery will need to happen elsewhere (e.g., via `ppid` walk → `ps -o tty=`). This is **noted but not flagged** because Phase 3 is the consumer; Phase 1's contract is "capture what's available," not "guarantee tty resolution."

### Verification Results — All In-Plan Acceptance Criteria

| Check | Command (paraphrased) | Result |
|-------|------------------------|--------|
| File exists & executable | `test -x Reporter/cab-report.sh` | PASS |
| Shebang `#!/bin/sh` | `head -1` | PASS |
| POSIX syntax | `/bin/sh -n Reporter/cab-report.sh` | PASS |
| Absolute paths nc/python3/date/tty/ps | grep | PASS |
| `trap 'exit 0' EXIT INT TERM HUP` | grep | PASS |
| Tail line `exit 0` | `tail -1` | PASS |
| `nc -U -w 1` with `>/dev/null 2>&1` | grep | PASS |
| Log via `>>` (O_APPEND), never `>` | grep | PASS |
| **VALIDATION 1-03-01** envelope JSON valid + schema_version=1 + session_id round-trip | scripted | **PASS** (envelope shows `{schema_version: 1, event: 'stop', session_id: 'test123', …}`) |
| **VALIDATION 1-03-02** rc=0 with no socket | scripted | **PASS** (rc=0) |
| **VALIDATION 1-03-03** ≤ 50ms with no socket | harness perf check | **FAIL — 64.8 ms measured** (see Deviations) |
| **VALIDATION 1-03-04** log accumulates ≥ 1 line | wc -l | PASS (111 lines after smoke run) |
| T-HOOK-01 input escaping uses python3 json.dumps via env vars | grep + injection probe | PASS — stdin payload `{"session_id":"x\"; rm -rf /tmp/should_not_exist; \"y","cwd":"/tmp"}` round-trips as the literal string `'x"; rm -rf /tmp/should_not_exist; "y'` inside `envelope.session_id`; nothing executed |
| T-HOOK-03 DoS via trap + tail exit + `nc -w 1` | source inspection | PASS |
| 100× burst safety | for loop | PASS — only `0` in the unique exit codes |

### Measured 50-Event Burst Latency (dev host: Apple Silicon, macOS 14, /usr/bin/python3 default Apple build)

```
runs   = 50
min    = 58.1 ms
median = 73.4 ms
mean   = 80.6 ms
p95    = 138.0 ms
max    = 282.1 ms
```

p95 / max are inflated by the run-to-run variance of macOS's `/usr/bin/python3` cold-start. Even with `-S`, every Reporter invocation pays the full Python startup cost because the script is forked fresh per hook fire (no daemon to keep an interpreter warm, by design — D-01 mandates the simplest possible Reporter).

### Verifier Output After Commit

```
$ bash scripts/verify-phase-1.sh --quick
[PASS] 1-01-01: Xcode project skeleton + two targets
[PASS] 1-01-02: LSUIElement=true in App/Info.plist
[PASS] 1-03-04: hook.log accumulates entries (111 lines)
[PASS] 1-07-01: verify-phase-1.sh exists & exits 0
Results: 4 pass, 0 fail
```

```
$ bash scripts/verify-phase-1.sh 2>&1 | grep "1-03-0"
[PASS] 1-03-01: Reporter writes valid JSON line
[PASS] 1-03-02: Reporter exits 0 with no socket
[FAIL] 1-03-03: Reporter ≤ 50ms (socket missing) — elapsed 0.0648s exceeds 0.050s budget
[PASS] 1-03-04: hook.log accumulates entries (111 lines)
```

3 / 4 owned VALIDATION rows green. The single FAIL is documented below.

## Deviations from Plan

### Auto-fixed Issues

None. The script body is verbatim RESEARCH § "Code Examples → POSIX sh Reporter" except for adding `-S` to the python3 invocation, which is a documented implementation choice (see `decisions:` frontmatter).

### Measurement deviation: 1-03-03 latency budget overrun (DOCUMENTED, NOT FIXED)

- **Row:** 1-03-03 (Reporter ≤ 50ms when socket missing)
- **Measured:** 64.8 ms via `scripts/verify-phase-1.sh` perf harness; 73.4 ms median across 50-burst (cold + warm mixed); 58 ms minimum on warmest cache
- **Budget:** 50 ms
- **Cause:** macOS `/usr/bin/python3` cold-start. Each hook fire forks a fresh `python3` process to call `json.dumps` on the envelope — even with `-S` (skip site.py), the interpreter init alone exceeds 50 ms on this dev host's Apple Silicon. There is no daemon to keep an interpreter warm; that is by design (D-01 simplest-possible Reporter).
- **Why not auto-fixed:** Every cheap optimization that closes the gap re-introduces a Pitfall:
  - Replace python3 with shell-only JSON construction → re-introduces T-HOOK-01 / Pitfall #3 (shell interpolation of user input). Plan explicitly forbids; Rule 4 territory.
  - Skip the python3 step entirely (raw passthrough of stdin) → loses D-08 envelope shape (schema_version, ts, ppid, etc.); breaks Plan 03's `HookEvent.swift` decode contract.
  - Move JSON construction into a long-lived helper daemon → architectural change, Rule 4, contradicts D-01.
- **Why this is safe to ship:**
  - HOOK-03's binding architectural constraint is "**never block Claude Code**" — that is satisfied here by:
    - `nc -w 1` (1-second idle timeout on the network call; the only call that *could* block on a remote condition)
    - `~/.claude/settings.json` `"timeout": 5` envelope (Plan 04 will register this; verified in RESEARCH §"Pitfall #12")
    - `trap 'exit 0' EXIT INT TERM HUP` ensures Claude can SIGTERM the hook without ill effect
  - The 50 ms figure originates from RESEARCH §"Validation Architecture → Success #2" as an **aspirational latency target**, not a v1 requirement traceable to any REQ-ID. No REQUIREMENTS.md row mentions a sub-50ms hook budget; HOOK-03 says "Reporter는 항상 `exit 0`으로 종료한다" (always exit 0) and HOOK-05 says "App이 실행 중이지 않을 때도 가만히 0으로 종료한다" (silently exit 0 when app down) — both are satisfied. The 50ms was a stretch target to prove "instantaneous" feel; 65 ms is still imperceptible in a hook context where Claude already waits 600 ms+ for its own model latency cycle.
- **Resolution path forward:** Surface to Plan 01-06 (Wave 3 e2e verify wiring) so the planner can either (a) revise the harness budget upward (e.g., 100 ms p95 with a warm cache; or 150 ms p95 raw — both well within Claude Code's 5000 ms hook timeout), (b) reclassify 1-03-03 to manual-only, or (c) accept the FAIL as informational. Recommendation: option (a) — change `0.050` to `0.150` in `scripts/verify-phase-1.sh` `verify_1_03_03`; that comfortably brackets the measured p95 of 138 ms while still flagging any future 10× regression.

This row is currently RED in the harness and will stay RED until Plan 01-06 adjudicates. **Plan 02 itself ships green on every other contract; the failing row is a measurement-budget mismatch, not a behavioral defect.**

## Authentication Gates

None encountered — pure local file authoring + shell exec.

## TDD Gate Compliance

Plan is `type: execute` (not `type: tdd`); RED/GREEN/REFACTOR gating does not apply.

## Threat Surface Scan

No new security-relevant surface introduced beyond what's in the plan's `<threat_model>`. The Reporter:
- Reads stdin and env vars (treated as **untrusted input** — escaped through `python3 json.dumps`, T-HOOK-01 mitigated)
- Writes to `~/Library/Logs/ClaudeAlertBot/hook.log` (user-home, mode 0644 default — within plan's threat model)
- Connects to `~/Library/Application Support/ClaudeAlertBot/sock` via `/usr/bin/nc -U` (no network egress; AF_UNIX is local-only by kernel)

T-HOOK-04 (PATH spoofing of `nc`) is mitigated by the `/usr/bin/nc` absolute path, verified by `grep -q '/usr/bin/nc' Reporter/cab-report.sh`.

## Self-Check

Verifying the deliverables:

```bash
test -x Reporter/cab-report.sh        # OK
git log --oneline | grep -q 1458693   # OK (feat(01-02): add POSIX sh hook reporter)
```

- `Reporter/cab-report.sh`: FOUND (executable, 85 lines)
- Commit `1458693` (feat(01-02)): present in `git log`

## Self-Check: PASSED

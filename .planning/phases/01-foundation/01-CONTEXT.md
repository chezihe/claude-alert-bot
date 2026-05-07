# Phase 1: Foundation - Context

**Gathered:** 2026-05-07
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the foundational plumbing that lets a Claude Code `Stop` hook land as a structured log line in a running, headless, ad-hoc-signed Swift app. Out of scope for this phase: any UI (no widget, no Settings window), elapsed-time computation, threshold filtering, sound, iTerm2 control, hook auto-installer, .dmg packaging.

In scope:
- Reporter shell script (POSIX `sh`) for the `Stop` hook
- AF_UNIX socket IPC server in the Swift app (`Network.framework` `NWListener`)
- Headless app skeleton (`LSUIElement=true`, single-instance enforcement)
- Ad-hoc codesign in build pipeline
- Hook log file at `~/Library/Logs/ClaudeAlertBot/hook.log` for debugging

Phase 1 ships nothing user-facing. Its deliverable is "an end-to-end pipe that proves the architecture works."

</domain>

<decisions>
## Implementation Decisions

### Reporter language & transport (DISCUSSED)

- **D-01:** Reporter is a POSIX `sh` script that writes one JSON line to an AF_UNIX socket via `/usr/bin/nc -U <socket-path>`. Absolute path to `/usr/bin/nc` is mandatory — `nc` flavor in the user's PATH may be GNU netcat which does not support `-U`.
- **D-02:** Reporter must always exit 0, including when the socket is unreachable (app not running) or when `nc` fails. Shell pattern: pipe + `|| true` + explicit `exit 0` at the end. This is a hard architectural constraint (Pitfall #1 — `exit 2` from Stop hook makes Claude Code loop).
- **D-03:** Reporter sends to the socket with a hard timeout (e.g., `nc -w 1`) so a stuck app cannot block Claude Code's turn end.

### Reporter install location (DISCUSSED)

- **D-04:** Reporter script is bundled in the `.app` (likely under `Contents/Resources/cab-report.sh`) AND copied to a stable user-data path on first run / hook install: `~/Library/Application Support/ClaudeAlertBot/cab-report.sh`. The path the user's `~/.claude/settings.json` references is the stable user-data copy, never the in-bundle path. App update overwrites the user-data copy with the freshly bundled version (version-aware copy: only overwrite if bundled is newer).
- **D-05:** Phase 5's HookInstaller will eventually do the auto-copy + settings.json patch. For Phase 1, this can be done by a manual setup script (`scripts/dev-install-hook.sh`) or by the developer copying the file by hand — Phase 1 is dev-only and need not have polished install UX.

### Claude's Discretion

The user did not select these areas for discussion. Default to standard choices and proceed; these can be revisited in planning if the planner has concerns. Decisions captured here become the working defaults:

- **D-06 (App identity / branding):** Bundle ID `com.claudealert.bot`. Display name "Claude Alert Bot". App icon and widget icon will be **original artwork** that nods at Claude (e.g., chat-bubble glyph) but does not use Anthropic's trademarked logo. Phase 2 will need icon assets; for Phase 1, a placeholder system glyph or simple monochrome SF Symbol is acceptable. Researcher / planner: do **not** download or embed any Anthropic-owned imagery.

- **D-07 (Phase 1 verification UX):** Phase 1's deliverable is verified via:
  1. **OSLog as the primary signal** — every received hook event logged to a dedicated subsystem (`com.claudealert.bot.hook`) and viewable with `log stream --predicate 'subsystem == "com.claudealert.bot.hook"'`.
  2. **Hook debug log file** at `~/Library/Logs/ClaudeAlertBot/hook.log`, written by the Reporter shell script independently of whether the app is running. Captures full env snapshot + ppid chain + tty for every fire (REQ HOOK-06).
  3. **A small `cab-test` CLI helper** (Swift command-line tool, ad-hoc-signed alongside the app) that fires a synthetic hook event into the socket. Used for "is the app receiving events" smoke checks during development. Lives at `.app/Contents/MacOS/cab-test` or in `scripts/`. Not a permanent user-facing feature — Phase 5 may relocate or hide it.

- **D-08 (JSON event envelope):** Reporter sends one line of JSON per event with this minimal schema (locked for Phase 2 to consume):
  ```json
  {
    "schema_version": 1,
    "event": "stop" | "user_prompt_submit",
    "session_id": "<claude code session_id from hook stdin>",
    "transcript_path": "<from hook stdin>",
    "cwd": "<env CWD or hook stdin cwd field>",
    "iterm_session_id": "<env ITERM_SESSION_ID>",
    "tty": "<output of /usr/bin/tty>",
    "ppid": <integer>,
    "claude_project_dir": "<env CLAUDE_PROJECT_DIR>",
    "ts": "<ISO 8601 with timezone>"
  }
  ```
  Missing fields are sent as JSON `null` (not omitted). App rejects events with unknown `schema_version`. Field set may grow in later phases — only `schema_version` bump on breaking change.

- **D-09 (Single-instance enforcement):** Use AF_UNIX socket bind exclusivity as the single-instance lock. Second app launch attempts to bind the same socket path, fails with `EADDRINUSE`, then exits 0 (or surfaces a brief log line). No NSDistributedNotificationCenter probe, no PID file. The socket path itself is the lock.

- **D-10 (Socket path):** `~/Library/Application Support/ClaudeAlertBot/sock`. App removes a stale socket file at startup before bind (only if no live listener) to recover from crashes. Reporter assumes this exact path.

- **D-11 (Build pipeline):** Single `scripts/build.sh` (or `make build`) that does `xcodebuild archive` + `codesign --force --deep --sign -` on the resulting `.app`. Build script is checked in. Phase 1 does not need `.dmg` — that's Phase 6. Distribution to test machines during Phase 1 = drag .app to /Applications manually.

- **D-12 (Project layout):** Single Xcode project with two targets: the main App and the `cab-test` CLI helper. Reporter is **not** an Xcode target — it's a plain `.sh` file in a top-level `Reporter/` directory, copied by the App into Resources at build time (Run Script Phase) and into user-data at install time. Repo root layout (suggested):
  ```
  /
  ├── ClaudeAlertBot.xcodeproj
  ├── App/                      (Swift source for main app)
  ├── CabTest/                  (Swift source for cab-test CLI)
  ├── Reporter/
  │   └── cab-report.sh
  ├── scripts/
  │   ├── build.sh
  │   └── dev-install-hook.sh   (Phase 1 dev convenience)
  └── .planning/
  ```

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project-level (always read)
- `.planning/PROJECT.md` — Core value, constraints, locked decisions, Out of Scope
- `.planning/REQUIREMENTS.md` — All 53 v1 REQ-IDs; Phase 1 covers HOOK-01, HOOK-03, HOOK-04, HOOK-05, HOOK-06, IPC-01, IPC-02, IPC-03, DIST-01, DIST-05
- `.planning/ROADMAP.md` — Phase 1 acceptance criteria + locked architectural decisions

### Research (Phase 1 directly relevant)
- `.planning/research/STACK.md` — Apple frameworks (`Network.framework`, `NWListener`, `NWEndpoint.unix`), ad-hoc codesign procedure, minimum macOS 14
- `.planning/research/ARCHITECTURE.md` — Two-process architecture, AF_UNIX SOCK_STREAM rationale (rejected file watcher / distributed notifications / URL scheme / XPC), hook contract, race-condition catalogue
- `.planning/research/PITFALLS.md` — #1 Hook `exit 2` looping, #2 ad-hoc-sign requirement on Apple Silicon, #5 distribution / `LSUIElement`, #9 concurrency races (relevant to socket listener concurrency model)
- `.planning/research/SUMMARY.md` §"Architecture Approach" + §"Phase 1: Foundation" — phase-1-specific synthesized recommendations

### External docs (verify during planning)
- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks) — Stop hook contract, JSON-on-stdin format, exit-code semantics (esp. why `exit 2` is dangerous), env vars (`CLAUDE_PROJECT_DIR`)
- [Apple — NWListener](https://developer.apple.com/documentation/network/nwlistener) — NWEndpoint.unix usage
- [Apple — NSWindow.CollectionBehavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct) — Phase 2, but reference now if any window code is touched
- BSD `nc(1)` man page — `-U` Unix socket mode, `-w` timeout flag (verify behavior on macOS 14)

### Not external specs
No project-internal ADRs exist yet. The `.planning/` documents above are the canonical record.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- None — repository is empty. Phase 1 creates the initial Xcode project, build script, Reporter script, and CLI helper from scratch.

### Established Patterns
- None established by this codebase. Patterns to follow are the ones lock-listed in ROADMAP.md "Locked Architectural Decisions" — those become the codebase patterns from Phase 1's first commit.

### Integration Points
- Outward: `~/.claude/settings.json` (hook registration, deferred to Phase 5; Phase 1 uses manual entry).
- Outward: `~/Library/Application Support/ClaudeAlertBot/sock` (socket path).
- Outward: `~/Library/Logs/ClaudeAlertBot/hook.log` (debug log).
- Outward: OSLog subsystem `com.claudealert.bot.hook`.

</code_context>

<specifics>
## Specific Ideas

- User explicitly asked for the **simplest** Reporter approach (chose A over B/C). Implication: planner should resist the temptation to add a Swift wrapper "for robustness" unless concrete evidence (e.g., `/usr/bin/nc` flag incompatibility on supported macOS versions) emerges in research.
- User has not yet provided icon artwork or branding direction. Treat this as a Phase 2 prerequisite blocker if not resolved by then; for Phase 1, placeholder is fine.

</specifics>

<deferred>
## Deferred Ideas

- **Hook auto-installer with idempotent JSON5 merge** — Phase 5 (INST-01..04, ONB-01).
- **macOS 15+ Gatekeeper "Open Anyway" docs + bypass-gatekeeper.command** — Phase 6 (DIST-03, DIST-04).
- **First-run onboarding wizard (3 screens: install hook → grant Automation → test)** — Phase 5 (ONB-01).
- **Real app icon / Anthropic-trademark-safe artwork** — by Phase 2 at the latest (WIDG-03 needs the icon visible).
- **`cab-test` CLI permanent placement / hidden-by-default** — revisit in Phase 5 onboarding (it could become "iTerm2 connection test" or stay as an internal tool).
- **Socket path collision recovery** — if a stale socket exists from a crashed instance, app removes it. If a *live* listener is bound (real conflict), app exits cleanly. This works for Phase 1 but may want richer UX in Phase 5.

</deferred>

---

*Phase: 1-Foundation*
*Context gathered: 2026-05-07*

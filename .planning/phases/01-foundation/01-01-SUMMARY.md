---
phase: 01-foundation
plan: 01
subsystem: build-scaffolding
tags: [macos, xcode, swift, scaffolding, xcodegen]
requires:
  - "Plan 01-00 (validation harness — used to verify 1-01-01 / 1-01-02)"
provides:
  - "ClaudeAlertBot.xcodeproj — two-target Xcode project (App + cab-test CLI)"
  - "Shared scheme ClaudeAlertBot (builds both targets) committed to xcshareddata"
  - "App/Info.plist with LSUIElement=true, com.claudealert.bot, NSAppleEventsUsageDescription, LSMinimumSystemVersion=14.0"
  - "App/main.swift — AppKit headless placeholder (Plan 03 takes over)"
  - "CabTest/main.swift — CLI placeholder (Plan 03 takes over)"
  - "project.yml — declarative source-of-truth for regenerating the .xcodeproj via xcodegen"
  - "Repo .gitignore covering build artifacts, DerivedData, xcuserdata"
affects:
  - "Plan 01-02 (Reporter shell) — drops cab-report.sh into Reporter/ which the postBuildScripts now copies"
  - "Plan 01-03 (Wave 2) — replaces both main.swift placeholders with real listener + synthetic injector"
  - "Plan 01-05 (Wave 3) — scripts/build.sh runs `xcodebuild -scheme ClaudeAlertBot archive` and ad-hoc signs the produced .app"
tech-stack:
  added:
    - "xcodegen 2.45.4 (developer-only build tool, brew-installed)"
    - "Swift 5 / Xcode 26 toolchain"
    - "AppKit (NSApplication accessory mode)"
  patterns:
    - "Pure-AppKit headless entry (no SwiftUI App scene) — avoids LSUIElement vs Settings-scene conflict per RESEARCH §Standard Stack"
    - "xcodegen project.yml as canonical project descriptor — pbxproj is a generated artifact that we still commit so downstream consumers don't need xcodegen"
    - "Embedded helper binary pattern: cab-test as `type: tool` declared as a build dependency of the App target with `embed: true, codeSign: false`"
    - "postBuildScripts copies Reporter/cab-report.sh into the .app's Resources at build time (D-04 wire-up)"
key-files:
  created:
    - "App/Info.plist"
    - "App/main.swift"
    - "CabTest/main.swift"
    - "ClaudeAlertBot.xcodeproj/project.pbxproj"
    - "ClaudeAlertBot.xcodeproj/project.xcworkspace/contents.xcworkspacedata"
    - "ClaudeAlertBot.xcodeproj/xcshareddata/xcschemes/ClaudeAlertBot.xcscheme"
    - "project.yml"
    - ".gitignore"
  modified: []
decisions:
  - "Used xcodegen rather than hand-authoring pbxproj or Xcode GUI clicks — 100% reproducible from a 70-line YAML; user_setup frontmatter declares it as a one-time `brew install xcodegen`."
  - "Added CODE_SIGN_IDENTITY=- + CODE_SIGN_STYLE=Manual + CODE_SIGNING_ALLOWED=YES to both targets' base settings (Rule 3 deviation — see below). Without these, plain `xcodebuild build` on Apple Silicon with no developer team selected can fail at the codesign step. D-11 calls for ad-hoc signing in scripts/build.sh anyway, so making Debug builds also use ad-hoc keeps Debug ↔ Release behavior consistent."
  - "Committed project.xcworkspace/contents.xcworkspacedata (the workspace's shared, single XML pointer file) — this is required for some `xcodebuild` configurations to find the project. xcuserdata/ inside the workspace is gitignored."
  - "Did NOT commit the build/ artifacts produced by the smoke build — those land in DerivedData/ outside the repo by default."
metrics:
  duration: "~10 minutes"
  tasks_completed: 2
  files_created: 8
  files_modified: 0
  completed: "2026-05-07"
---

# Phase 1 Plan 01: Xcode Project Skeleton — Summary

**One-liner:** Two-target Xcode project (`ClaudeAlertBot` app + `cab-test` CLI) generated from a 70-line `project.yml` via xcodegen, with `LSUIElement=true` headless Info.plist, AppKit `.accessory` placeholder `main.swift`, ad-hoc-sign-friendly Debug build settings, and a shared scheme — ready for Plan 02 (Reporter) and Plan 03 (real App + cab-test code) to drop files into.

## What Shipped

### Repo layout (D-12)

```
/
├── App/
│   ├── Info.plist          (LSUIElement=true, com.claudealert.bot, NSAppleEventsUsageDescription)
│   └── main.swift          (placeholder — AppKit accessory; Plan 03 replaces)
├── CabTest/
│   └── main.swift          (placeholder — Plan 03 replaces)
├── Reporter/               (empty — Plan 02 drops cab-report.sh here)
├── scripts/
│   └── verify-phase-1.sh   (from Plan 00 — Plan 05 will add build.sh)
├── ClaudeAlertBot.xcodeproj/
│   ├── project.pbxproj
│   ├── project.xcworkspace/contents.xcworkspacedata
│   └── xcshareddata/xcschemes/ClaudeAlertBot.xcscheme   (shared, builds both targets)
├── project.yml             (xcodegen source of truth)
├── .gitignore
└── .planning/
```

### Two Xcode targets

| Target | Type | Sources | Bundle ID / Output | Notes |
|--------|------|---------|--------------------|-------|
| `ClaudeAlertBot` | application | `App/` | `com.claudealert.bot` | App bundle. Embeds `cab-test` (no codesign — top-level codesign covers it). Has a Run Script Phase that copies `Reporter/cab-report.sh` to `Contents/Resources/cab-report.sh` if present. |
| `cab-test` | tool | `CabTest/` | unix CLI | Built into `${BUILT_PRODUCTS_DIR}/cab-test`, embedded inside the App at build time so it ships in the same `.app`. |

### Info.plist keys (per RESEARCH "Info.plist keys (Phase 1)")

| Key | Value | Purpose |
|-----|-------|---------|
| `LSUIElement` | `true` | DIST-05 — accessory mode (no Dock, no menu bar, no Cmd-Tab). |
| `CFBundleIdentifier` | `com.claudealert.bot` | D-06 (locked). |
| `LSMinimumSystemVersion` | `14.0` | macOS 14 Sonoma minimum (locked). |
| `NSAppleEventsUsageDescription` | "Claude Alert Bot needs to switch focus to your iTerm2 tab when a Claude Code task completes." | Phase-3 prerequisite (TCC permission text reserved early per CONTEXT D-06). |

xcodegen rewrote the file during `xcodegen generate` (replaced `CFBundleDevelopmentRegion`'s value with `$(DEVELOPMENT_LANGUAGE)`, kept all 4 verify-required keys intact). All four keys round-trip through `PlistBuddy`.

### Shared scheme

`ClaudeAlertBot.xcscheme` lives in `xcshareddata/xcschemes/` (committed). Building it triggers both `ClaudeAlertBot` and `cab-test` targets via `BuildableProductRunnable` references. `xcodebuild -scheme ClaudeAlertBot` works out-of-the-box for downstream `scripts/build.sh` (Plan 05).

## Verification Run

```
$ xcodebuild -list -project ClaudeAlertBot.xcodeproj
Information about project "ClaudeAlertBot":
    Targets:
        ClaudeAlertBot
        cab-test
    Build Configurations:
        Debug
        Release
    Schemes:
        cab-test
        ClaudeAlertBot
```

```
$ xcodebuild -project ClaudeAlertBot.xcodeproj -scheme ClaudeAlertBot \
             -configuration Debug -destination 'platform=macOS' build
... (snip) ...
** BUILD SUCCEEDED **
```

```
$ bash scripts/verify-phase-1.sh --quick
[PASS] 1-01-01: Xcode project skeleton + two targets
[PASS] 1-01-02: LSUIElement=true in App/Info.plist
[FAIL] 1-03-04: hook.log accumulates entries — ...missing
[PASS] 1-07-01: verify-phase-1.sh exists & exits 0

Results: 3 pass, 1 fail
```

`1-03-04` FAIL is **expected** — that row depends on Plan 02's `Reporter/cab-report.sh`, which is the very next plan. The 2/3 → 3/4 PASS transition (rows `1-01-01` + `1-01-02` flipping green) is exactly the post-Plan-01 state Plan 00 predicted in its Currently Green vs. Currently Red table.

## What's Still Placeholder

- `App/main.swift` — calls `setActivationPolicy(.accessory)` then `app.run()`, but has **no AppDelegate**, **no NWListener**, **no OSLog wiring**. Running the produced `.app` will hang in the run loop doing nothing (no socket bound, no events processed). This is intentional Phase-1 contract; Plan 03 (Wave 2) replaces this file.
- `CabTest/main.swift` — prints one diagnostic line and exits 0. Plan 03 replaces it with synthetic-event-injection logic against the AF_UNIX socket.
- `Reporter/` — directory exists (created in Task 1) but is empty. Plan 02 drops `cab-report.sh` into it; the `postBuildScripts` step in `project.yml` already references `${SRCROOT}/Reporter/cab-report.sh` and silently no-ops if the file is missing (current state). Once Plan 02 lands the file, the next `xcodebuild` run will copy it into `Contents/Resources/` automatically.

## Known Build Warnings

```
warning: Run script build phase 'Embed Reporter shell script' will be run during every build
because it does not specify any outputs.
```

This is cosmetic. It only matters for incremental-build performance; Phase 1 hasn't established build-cache discipline yet, and the warning will be addressed (or accepted) when Plan 02 commits the actual shell script. Adding output dependencies now while the source file doesn't yet exist would just shift the warning to a different one ("input file does not exist"). No action.

## Acceptance Criteria — All Met

**Task 1**
- [x] `App/`, `CabTest/`, `Reporter/`, `scripts/` directories exist
- [x] `.gitignore` excludes `build/`, `DerivedData/`, `.DS_Store`, `*.xcuserstate`, `xcuserdata/`, `*.xcarchive`
- [x] No spurious files added to `Reporter/` or `scripts/` (other plans own them)

**Task 2**
- [x] `project.yml` exists with two targets (`ClaudeAlertBot:` and `cab-test:` lines present)
- [x] `ClaudeAlertBot.xcodeproj/project.pbxproj` exists
- [x] `xcodebuild -list -project ClaudeAlertBot.xcodeproj` exits 0
- [x] Both targets registered (`grep -cE '^[[:space:]]+(ClaudeAlertBot|cab-test)$'` ≥ 2 — actual count 4 because both targets appear under both `Targets:` and `Schemes:` sections)
- [x] `cab-test` referenced in pbxproj
- [x] `LSUIElement=true` (PlistBuddy-verified)
- [x] `CFBundleIdentifier=com.claudealert.bot` (PlistBuddy-verified)
- [x] `LSMinimumSystemVersion=14.0` (PlistBuddy-verified)
- [x] `NSAppleEventsUsageDescription` mentions "iTerm2"
- [x] `App/main.swift` contains `setActivationPolicy(.accessory)`
- [x] `MACOSX_DEPLOYMENT_TARGET = 14.0` in pbxproj
- [x] Shared scheme committed at `ClaudeAlertBot.xcodeproj/xcshareddata/xcschemes/ClaudeAlertBot.xcscheme`
- [x] `bash scripts/verify-phase-1.sh --quick` shows `[PASS] 1-01-01` and `[PASS] 1-01-02` (2 of 2 plan-01 rows green)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Added ad-hoc code-sign settings to both targets**
- **Found during:** Task 2, before running the smoke `xcodebuild build`.
- **Issue:** Plan's `project.yml` did not declare `CODE_SIGN_IDENTITY`. On a developer machine with no Apple Developer Team selected, plain `xcodebuild -scheme ClaudeAlertBot build` defaults to "Automatic" signing and fails to find a signing identity, blocking the Task 2 build smoke check (acceptance criterion).
- **Fix:** Added `CODE_SIGN_IDENTITY: "-"`, `CODE_SIGN_STYLE: Manual`, `CODE_SIGNING_ALLOWED: YES` under `settings.base` for both targets in `project.yml`. This pins ad-hoc signing for Debug too — consistent with D-11's "ad-hoc-sign from day one" mandate. Plan 05's `scripts/build.sh` will continue to do an explicit `codesign --force --deep --sign -` on the archived bundle for the production path; this change just makes Debug builds work without an Apple ID.
- **Files modified:** `project.yml` (and consequently the regenerated `ClaudeAlertBot.xcodeproj/project.pbxproj`).
- **Commit:** `1a01531`.

### Implementation choices within plan freedom

- xcodegen reorganized `App/Info.plist` during `xcodegen generate` (e.g., changed `CFBundleDevelopmentRegion` value from `en` to `$(DEVELOPMENT_LANGUAGE)`, dropped `NSHumanReadableCopyright`). All four verify-required keys (LSUIElement, CFBundleIdentifier, LSMinimumSystemVersion, NSAppleEventsUsageDescription) are preserved exactly because they are pinned in `project.yml`'s `info.properties`. Did not "fix back" the xcodegen output — per advisor, that would just be clobbered on next regenerate. The acceptance criteria all pass against xcodegen's output.

## Authentication Gates

None encountered — all work is local file authoring + xcodegen + xcodebuild on the developer's machine.

## TDD Gate Compliance

Plan is `type: execute` (not `type: tdd`); RED/GREEN/REFACTOR gating does not apply.

## Threat Surface Scan

No new security-relevant surface introduced beyond what's in the plan's `<threat_model>`. The committed Info.plist text reserves `NSAppleEventsUsageDescription` for Phase 3 — this is documented permission copy, not actionable surface yet (the app does not invoke any AppleEvents in Phase 1).

## Self-Check

Verifying the deliverables before declaring done:

- `App/Info.plist`: FOUND
- `App/main.swift`: FOUND
- `CabTest/main.swift`: FOUND
- `ClaudeAlertBot.xcodeproj/project.pbxproj`: FOUND
- `ClaudeAlertBot.xcodeproj/xcshareddata/xcschemes/ClaudeAlertBot.xcscheme`: FOUND
- `project.yml`: FOUND
- `.gitignore`: FOUND
- Commit `8f04e24` (Task 1, .gitignore + dirs): present in `git log`
- Commit `1a01531` (Task 2, Xcode project): present in `git log`

## Self-Check: PASSED

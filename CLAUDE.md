## Project

**Claude Alert Bot**

Claude Code 작업이 끝났을 때 macOS 화면에 클로드 아이콘 플로팅 위젯으로 알려주는 네이티브 macOS 앱. 위젯을 클릭하면 해당 작업이 실행됐던 iTerm2 탭/창으로 즉시 점프한다. 본인 사용 + 다른 macOS Claude Code 사용자에게도 배포할 목적의 도구.

**Core Value:** **Claude Code 사용자가 자리를 비웠을 때, 길게 걸린 작업의 완료를 놓치지 않고 바로 그 터미널로 복귀할 수 있다.** 알림이 떠도 어느 세션 것인지 헷갈리거나 클릭이 잘못된 터미널을 여는 순간 가치가 무너진다 — "정확한 그 세션으로의 점프"가 핵심.

### Constraints

- **OS**: macOS 14 Sonoma 이상 (`MenuBarExtra` 안정성, `SMAppService.mainApp`, `Network.framework` UDS endpoint 모두 14에서 안정)
- **터미널**: iTerm2 only — MVP 범위
- **Tech stack**: Swift / SwiftUI + AppKit interop (NSPanel + NSHostingView). 외부 Swift 의존성 0. `Network.framework` AF_UNIX 소켓으로 hook ↔ App IPC
- **빌드 환경**: Xcode 15.4+ 필요 (Mac 개발자만 빌드 가능). 사용자는 빌드 산출물만 받음
- **서명**: Apple Developer Program 미가입. **Apple Silicon에서 실행되려면 ad-hoc 서명(`codesign --force --deep --sign -`)은 필수** (없으면 실행 자체 불가 — Gatekeeper 이전의 로드 단계 차단). Apple Developer 가입 없이 무료로 가능
- **Gatekeeper 우회**: macOS 15+ 에서는 우클릭 → "열기" 단축이 제거됨. 사용자는 **System Settings → Privacy & Security → "Open Anyway"** 절차를 1회 거쳐야 하며, DMG에 포함된 `bypass-gatekeeper.command` 헬퍼(`xattr -cr` 실행)로 대안 제공 가능
- **외부 의존**: Claude Code 설치 + iTerm2 설치 필수
- **Hook 등록**: Claude Code의 `Stop` hook + `UserPromptSubmit` hook **둘 다** 필요 (시작/종료 상관으로 경과 시간 계산). App이 `~/.claude/settings.json`에 멱등 병합으로 자동 등록
- **AppleScript 자동화 권한**: 첫 사용 시 macOS가 "Claude Alert Bot이 iTerm2를 제어하려 합니다" 권한 다이얼로그를 띄움 — 사용자가 허용해야 함. `NSAppleEventsUsageDescription` Info.plist 키 필수

## Technology Stack

## TL;DR — One-Line Recommendations
| Concern | Pick | Why (one line) |
|---|---|---|
| Min OS | **macOS 14 Sonoma** | `MenuBarExtra` matured + modern SwiftUI scene APIs without 13-era bugs |
| Floating widget | **`NSPanel` (subclass) wrapped via `NSViewRepresentable`/`NSWindowController` + `NSHostingView`** with `level = .floating` (or `.statusBar`) and `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` | Pure SwiftUI `Window` scene cannot pin above all spaces; only NSPanel can |
| Hook → app IPC | **Unix domain socket via `Network.framework` (`NWListener` + `NWEndpoint.unix`)** | Local, fast, no entitlements, survives concurrent hook fires, structured JSON; not sandboxed (we are not sandboxing) |
| iTerm2 control | **`NSAppleScript` (compile-once, run-many)** with explicit `NSAppleEventsUsageDescription` and tab-by-PID lookup | Highest-fidelity iTerm2 API surface; ScriptingBridge headers are creaky and Process+osascript is slower / harder to error-handle |
| Sound | **`AVAudioPlayer` (AVFoundation)** | Reliable across 14/15/26; NSSound has known crash regressions on macOS 26 in CoreAudio init |
| Settings UI | **SwiftUI `Settings { … }` scene + `@AppStorage`** | Standard, free, no third-party state libs needed |
| Dock hide | **`LSUIElement = true`** in Info.plist (accessory app) | Required because the app should be invisible until a Stop event |
| .dmg packaging | **`create-dmg` (sindresorhus, Node CLI) — single command, no config** | Simpler than `dmgbuild`; produces a good-looking DMG that works on Apple Silicon |
| Code signing | **Ad-hoc sign (`codesign -s -`) every build** | Required on Apple Silicon to launch at all; does not require a paid developer account |
| First-run UX | Document `xattr -cr /Applications/ClaudeAlertBot.app` in README | Right-click→Open is **dead** in macOS 15+; this is now the canonical workaround |
| Build system | **Xcode project** (not SwiftPM-only) | `MenuBarExtra` + asset catalog + Info.plist editing is path-of-least-resistance in Xcode |
## Recommended Stack
### Core Technologies
| Technology | Version | Purpose | Why Recommended |
|---|---|---|---|
| **Swift** | 5.10 (Xcode 15.4) or Swift 6 (Xcode 16+) | Application language | Locked by `PROJECT.md`. Swift 6 strict concurrency is opt-in; we can ship in Swift 5 mode and migrate later |
| **SwiftUI** | macOS 14 SDK | UI framework for settings + widget content | `MenuBarExtra` (macOS 13+), `Settings` scene, `@AppStorage` make this app trivial |
| **AppKit** | macOS 14 SDK | `NSPanel`, `NSWindow.Level`, `NSWindow.CollectionBehavior`, `NSHostingView` | SwiftUI-only `Window` scene cannot produce a panel that floats above all Spaces; AppKit interop is non-negotiable |
| **Foundation / Network.framework** | macOS 14 SDK | Unix-domain-socket IPC server inside the app | `NWListener` + `NWEndpoint.unix(path:)` is the modern Apple-blessed way to do local IPC; replaces Berkeley sockets boilerplate |
| **AVFoundation (`AVAudioPlayer`)** | macOS 14 SDK | Play notification sound once on event | NSSound has reported regressions in macOS 26 (CoreAudio init crash); AVAudioPlayer is the durable choice |
| **Carbon `NSAppleScript`** | macOS 14 SDK | Drive iTerm2 (focus tab/window, look up by PID) | AppleScript is iTerm2's most complete external automation surface. `NSAppleScript` compiles once, executes repeatedly, and surfaces errors as `NSDictionary` |
| **UserNotifications (`UNUserNotificationCenter`)** | macOS 14 SDK | (Optional, secondary) System banner *fallback* if widget fails | NOT the primary mechanism — banners auto-dismiss, which violates the core requirement. Useful only as a backup notify channel |
### Supporting Libraries
| Library | Version | Purpose | When to Use |
|---|---|---|---|
| **`KeyboardShortcuts` (sindresorhus)** | 2.x | (Optional) Global hotkey to manually surface the widget | Only if we add "press hotkey to peek the queue" later — not MVP |
| **`Defaults` (sindresorhus)** | 8.x | Type-safe `@AppStorage` replacement | Skip for MVP; built-in `@AppStorage` covers our 3-4 settings |
| **`LaunchAtLogin` (sindresorhus)** | 5.x (uses SMAppService under the hood) | Auto-start on login | Add when v1 is stable; uses `SMAppService.mainApp.register()` on macOS 13+ |
| **`Sparkle`** | — | Auto-updater | **Explicitly out of scope per `PROJECT.md`**. Do not add |
### Development Tools
| Tool | Purpose | Notes |
|---|---|---|
| **Xcode 15.4+** (16 preferred) | IDE, build, code-sign, archive | Required for SwiftUI macOS 14 SDK. Xcode 16 ships Swift 6 toolchain |
| **`xcodebuild`** | CI/release builds from CLI | `xcodebuild -scheme ClaudeAlertBot -configuration Release -archivePath …` then `-exportArchive` |
| **`codesign`** (`-s -`) | Ad-hoc sign the `.app` bundle | Required on Apple Silicon for the binary to launch at all. Add `--deep --force --options=runtime` for safety |
| **`create-dmg`** (npm, sindresorhus) | Build the distribution `.dmg` | Single command: `create-dmg ClaudeAlertBot.app`. Produces an Applications-symlink-style DMG, no config file needed |
| **Make / shell `release.sh`** | Glue archive → ad-hoc sign → create-dmg | Project repo should ship `scripts/release.sh` so a release is one command |
| **(Skip) Sparkle, fastlane, notarytool** | — | Skipped: per-project decision to avoid Apple Developer Program ($99/yr) |
## Installation (developer machine)
# Build dependencies (one-time)
# Packaging dependencies (Node-based; install once)
# Optional: a JSON pretty-printer for the hook script
## IPC Mechanism — Hook Script → App
| Mechanism | Verdict | Notes |
|---|---|---|
| **Unix domain socket (`NWListener` + `NWEndpoint.unix`)** | **RECOMMENDED** | Local-only by file-system permissions. Fast (sub-ms). Survives multiple concurrent hook fires (one connection per fire). JSON-line protocol is trivial. App owns lifecycle of `/tmp/claude-alert-bot.sock` (or `~/Library/Application Support/ClaudeAlertBot/ipc.sock`). Hook script writes via `nc -U` or a tiny Swift CLI helper. **No entitlements, no sandboxing concerns** |
| **Distributed Notifications (`CFNotificationCenter` / `DistributedNotificationCenter`)** | Rejected | Designed for stateless broadcast events between apps. Per Apple, posting is "expensive" and goes through `distnoted`. Hard to attach a JSON payload (only a `userInfo` dictionary, with size constraints). Fragile under load |
| **URL scheme (`open claudealertbot://stop?...`)** | Rejected | Causes `LaunchServices` to *activate* the app (defeating LSUIElement-quiet behavior unless we work around it). Encoding the JSON payload as a URL is gross. Also competes with system URL handlers |
| **XPC service** | Rejected | XPC is *brilliant* but designed for app-bundled helper services (signed mach service names). Connecting from a free-standing shell script requires `launchd`-registered mach services and a privileged `LaunchAgents` plist — overkill, brittle for unsigned distribution |
| **File watcher on a "drop directory"** (e.g. `~/Library/.../inbox/*.json`, watched with `DispatchSource.makeFileSystemObjectSource`) | Acceptable fallback | Dead simple, survives app-not-running (events queue on disk). Slightly less elegant than a socket; needs a janitor to delete consumed files. Keep this as a **secondary path** if socket fails (e.g. permission/race issues) |
| **HTTP hook (Claude Code native `"type": "http"`)** | Strong alternative | Claude Code supports `"type": "http"` hooks that POST the payload to a URL. The app can host an `NWListener` on `127.0.0.1:<random>` and register that URL in `settings.json`. **Pro:** zero shell-script glue, payload is the raw JSON. **Con:** ephemeral port complicates `settings.json` (need a fixed port) |
### Hook script glue (if going the socket route)
#!/bin/sh
# claude-alert-bot-hook.sh
## iTerm2 Automation — AppleScript Binding
| Approach | Verdict | Notes |
|---|---|---|
| **`NSAppleScript` (compile once, execute many)** | **RECOMMENDED** | Native, no subprocess overhead. Compile the script once at app launch into an `NSAppleScript` instance; mutate parameters via `executeAndReturnError(_:)`. Surface `NSDictionary` errors. AppleScript is iTerm2's richest external API (windows → tabs → sessions hierarchy with `tty`/`name`/`pid` properties exposed) |
| **ScriptingBridge (typed Obj-C bridge)** | Rejected for this project | Header generation (`sdef`/`sdp`) is creaky in 2025/2026. Generated `iTerm2.h` requires manual import and sometimes regeneration after iTerm updates. Negligible perf benefit over `NSAppleScript` for our infrequent calls |
| **`Process` + `/usr/bin/osascript`** | Use only as escape hatch | Spawns a subprocess each call (~30-100ms overhead). Useful for one-off scripts during development; not for production hot-path |
| **iTerm2 Python API** | Rejected | Excellent for iTerm-internal scripts but requires the user to run a Python daemon and manage `~/Library/ApplicationSupport/iTerm2/Scripts`. Not appropriate for an external Swift app |
## Sound Playback
| API | Verdict | Notes |
|---|---|---|
| **`AVAudioPlayer`** | **RECOMMENDED** | Bundled, reliable, supports volume, completion callbacks, repeat counts. Stable across 14/15/26 |
| **`NSSound`** | Avoid for new code in 2025/2026 | Reports of CoreAudio init crashes on macOS 26 (`caulk` allocator path). Adequate on 14/15 but no upside vs AVAudioPlayer |
| **`UNNotificationSound` (UserNotifications)** | Use *only* if also delivering a `UNUserNotification` | Tightly coupled to a notification's lifetime; we explicitly do NOT want auto-dismissing system notifications |
| **`AudioServicesPlayAlertSound` / system sound** | Use only for the "ding" mode | Bypasses the user's volume slider; surprisingly loud. Skip |
## Floating Widget — `NSPanel` Configuration
## Settings UI
## Distribution: Unsigned `.dmg` Reality in 2025/2026
| macOS version | Right-click → Open | System Settings "Open Anyway" | `xattr -cr` workaround |
|---|---|---|---|
| ≤ 14 (Sonoma) | Works | Works | Works |
| 15.0 (Sequoia) | **Removed** | Works (extra clicks: launch fails → System Settings → Privacy & Security → "Open Anyway") | Works |
| 15.1+ (Sequoia) | **Removed** | Works but reportedly buggy in some 15.1 builds | Works |
| 26 (Tahoe) | **Removed** | Works, requires admin password | Works |
### Recommended distribution flow
## Minimum macOS Version — Recommendation
| Factor | macOS 13 Ventura | macOS 14 Sonoma | macOS 15 Sequoia |
|---|---|---|---|
| `MenuBarExtra` available | Yes (13.0+) | Yes, polished | Yes |
| `SMAppService` for login items | Yes | Yes | Yes |
| `Settings` scene | Yes | Yes | Yes |
| SwiftUI macOS bug surface | High (especially around MenuBarExtra opening windows) | Materially better | Best |
| Network.framework UDS | Yes | Yes | Yes |
| User adoption (per Apple, end-2025/early-2026) | Long tail | Majority | Largest single share |
| Cost of supporting | Adds `if #available` branches | None | Drops a chunk of users |
## Alternatives Considered
| Recommended | Alternative | When to Use Alternative |
|---|---|---|
| Unix domain socket (NWListener) | HTTP `127.0.0.1:<port>` + Claude Code's native `"type": "http"` hook | If you want zero shell-script glue and don't mind hard-coding a port. Equally viable; pick one and commit |
| Unix domain socket | File-watcher on a drop directory | If the app is not always running and you want hook events to queue on disk for next launch. Add as a hardening measure post-MVP |
| NSPanel | SwiftUI `Window` scene + `.windowLevel(.floating)` | macOS 15+ only and even then `collectionBehavior` is not exposed. Defer until SwiftUI catches up |
| `NSAppleScript` (in-process) | `Process` + `osascript` subprocess | Quick prototyping or one-off debugging — not production hot-path |
| `AVAudioPlayer` | `NSSound` | Only for legacy code; new code should not adopt NSSound in 2026 |
| `create-dmg` (sindresorhus) | `dmgbuild` (Python) | If your release tooling is Python-native and you want the deeper customization knobs (license panel, custom icon positions). Equivalent quality |
| `create-dmg` | `node-appdmg` | Don't — last meaningful release was 3 years ago, near-stagnant |
| MenuBarExtra-only widget | Standalone NSPanel without menu bar | Pure spawn-on-event with no menu bar entry. Skipped: a menu bar icon is the cheapest discoverability and a natural place for "Settings…" / "Quit" |
| LSUIElement accessory app | Full Dock app (LSUIElement=false) | If users complain they can't find the app. Can switch to dock-and-hide pattern via `NSApp.setActivationPolicy(.accessory)` at runtime |
## What NOT to Use
| Avoid | Why | Use Instead |
|---|---|---|
| **`UNUserNotificationCenter` banners as primary notify** | Auto-dismiss after seconds — directly violates "위젯은 사용자가 클릭할 때까지 잔존" | NSPanel floating widget (primary). `UNUserNotificationCenter` may stay as an *optional fallback* notification |
| **`NSSound`** | Reported macOS 26 CoreAudio init crashes; no functional advantage | `AVAudioPlayer` |
| **ScriptingBridge for iTerm2** | Header churn, regeneration pain across iTerm2 updates, no perf win for our few-call workload | `NSAppleScript` (compile once, execute many) |
| **XPC for hook → app IPC** | Requires registered mach service name and `LaunchAgents` plist — incompatible with frictionless unsigned distribution | Unix domain socket via `Network.framework` |
| **Distributed Notifications** | "Expensive" per Apple docs; payload-as-userInfo is awkward; system-wide broadcast overhead is wrong tier | Unix domain socket |
| **URL scheme as IPC** | Activates app via LaunchServices (defeats accessory/quiet behavior); JSON-as-URL encoding is grim | Unix domain socket |
| **Shell `Process` + `osascript` in hot path** | ~30–100ms subprocess fork-exec per call; `NSAppleScript` is in-process and 10–100× faster | `NSAppleScript` |
| **Sandboxing the app** | Breaks Network.framework Unix-socket IPC and AppleScript automation in subtle ways | Don't sandbox; we are not Mac-App-Store-distributing |
| **Sparkle auto-updater** | Out of scope per `PROJECT.md` (manual `.dmg` updates for v1) | None — defer |
| **node-appdmg** | Effectively unmaintained (~3 years since meaningful release) | `create-dmg` (sindresorhus) or `dmgbuild` |
| **Right-click → Open instructions in README** | Removed in macOS 15+; will confuse users | Document System Settings flow + provide `bypass-gatekeeper.command` helper script using `xattr -cr` |
| **SwiftPM `Package.swift` as the ONLY build artifact** | Producing a launchable `.app` bundle with Info.plist, asset catalog, code signing requires Xcode project plumbing that SwiftPM alone makes painful | Xcode `.xcodeproj` (can still use SwiftPM for any future deps) |
## Stack Patterns by Variant
- Add a thin "TerminalAdapter" protocol; each terminal (Terminal.app, Warp, Ghostty) gets a concrete impl
- Terminal.app: AppleScript (`tell application "Terminal"`); same `NSAppleScript` machinery
- Warp / Ghostty: AppleScript surface is much thinner; may need URL scheme or x-callback-url; **defer**
- Switch ad-hoc sign to Developer ID Application certificate
- Add `notarytool submit … --wait` step before `create-dmg`
- DMG-then-staple (`xcrun stapler staple`)
- Drop all README instructions about `xattr -cr` / "Open Anyway"
- This is a one-day migration; nothing in the recommended stack precludes it
- Skip `MenuBarExtra`, set `LSUIElement=true`, and provide settings via a CLI subcommand or a hidden hotkey
- Trade-off: discoverability tanks; "how do I quit / change settings?" becomes a support issue
## Version Compatibility
| Package A | Compatible With | Notes |
|---|---|---|
| Xcode 15.4 | macOS 14 SDK, Swift 5.10 | Minimum recommended toolchain |
| Xcode 16.x | macOS 14 + 15 SDK, Swift 6 | Optional; use `-swift-version 5` to defer Swift 6 strict concurrency for v1 |
| `MenuBarExtra` | macOS 13.0+ | Available but with bugs on 13.x; recommend 14.0 deployment target |
| `Network.framework` UDS (`NWEndpoint.unix`) | macOS 10.15+ | Stable since Catalina; no concerns |
| `NSAppleScript` | macOS 10.0+ | Carbon-era but supported indefinitely |
| `AVAudioPlayer` | macOS 10.7+ | Stable |
| `create-dmg` (npm) 8.x | macOS 11+ host machine | Build-time tool; runtime DMG works on macOS 10.13+ |
## Sources
- [NSWindow.CollectionBehavior — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct) — HIGH (official)
- [canJoinAllSpaces — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces) — HIGH (official)
- [NSPanel patterns for SwiftUI — Fazm Blog (2024-2026)](https://fazm.ai/blog/swiftui-floating-panel) — MEDIUM
- [SwiftUI/MacOS: Floating Window/Panel — Itsuki, Level Up Coding](https://levelup.gitconnected.com/swiftui-macos-floating-window-panel-4eef94a20647) — MEDIUM
- [Make a floating panel in SwiftUI for macOS — Cindori](https://cindori.com/developer/floating-panel) — MEDIUM
- [Showing Settings from macOS Menu Bar Items: A 5-Hour Journey — Peter Steinberger (2025)](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items) — MEDIUM (current; documents 13.x quirks justifying 14.0 minimum)
- [NWListener — Apple Developer Documentation](https://developer.apple.com/documentation/network/nwlistener) — HIGH (official)
- [Building a server-client application using Apple's Network Framework — RDerik](https://rderik.com/blog/building-a-server-client-application-using-apple-s-network-framework/) — MEDIUM
- [NWListener with NWEndpoint.unix — Apple Developer Forums](https://developer.apple.com/forums/thread/719635) — MEDIUM
- [iTerm2 AppleScript Documentation](https://iterm2.com/documentation-scripting.html) — HIGH (official)
- [NSSound — Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nssound) — HIGH (official)
- [Audio API Overview — objc.io](https://www.objc.io/issues/24-audio/audio-api-overview/) — MEDIUM
- [MenuBarExtra — Apple Developer Documentation](https://developer.apple.com/documentation/SwiftUI/MenuBarExtra) — HIGH (official)
- [Build a macOS menu bar utility in SwiftUI — NilCoalescing](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/) — MEDIUM
- [Hiding Your App's Icon From the Dock Properly — Bures DV](https://buresdv.substack.com/p/swift-protip-hiding-your-apps-icon) — MEDIUM
- [create-dmg (sindresorhus, npm) — GitHub](https://github.com/sindresorhus/create-dmg) — HIGH (active, sindresorhus, current 8.x)
- [dmgbuild — PyPI](https://pypi.org/project/dmgbuild/) — HIGH (official)
- [macOS distribution — code signing, notarization, quarantine — rsms gist](https://gist.github.com/rsms/929c9c2fec231f0cf843a1a746a416f5) — MEDIUM (excellent overview)
- [Open unsigned applications on macOS Sequoia and newer — Hacks Guide Wiki](https://wiki.hacks.guide/wiki/Open_unsigned_applications_on_macOS_Sequoia_and_newer) — MEDIUM (current)
- [Apple Forces The Signing Of Applications In MacOS Sequoia 15.1 — Hackaday](https://hackaday.com/2024/11/01/apple-forces-the-signing-of-applications-in-macos-sequoia-15-1/) — MEDIUM
- [macOS Sequasia removes the Control-click method to bypass Gatekeeper — iDownloadBlog](https://www.idownloadblog.com/2024/08/07/apple-macos-sequoia-gatekeeper-change-install-unsigned-apps-mac/) — MEDIUM
- [Allow downloaded Apps to Open in macOS Tahoe — SwissMacUser](https://swissmacuser.ch/fix-macos-tahoe-app-is-damaged-and-cant-be-opened-move-trash/) — MEDIUM
- [Hooks reference — Claude Code Docs](https://code.claude.com/docs/en/hooks) — HIGH (official; verified Stop hook fields and HTTP hook support)
- [Claude Code Hooks: Complete Guide to All 12 Lifecycle Events — claudefa.st](https://claudefa.st/blog/tools/hooks/hooks-guide) — MEDIUM

## Conventions

Conventions not yet established. Will populate as patterns emerge during development.

## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.

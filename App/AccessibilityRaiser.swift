// App/AccessibilityRaiser.swift — Phase 3 D3-21 cross-Space window raise.
// Why: AppleScript `tell w to set index to 1; activate` cannot raise an iTerm2 window
// that lives in a different macOS Mission Control Space (e.g. each iTerm window in its
// own full-screen Space). kAXRaiseAction on an AXUIElement DOES switch Spaces — this
// is how every macOS window switcher (AltTab, Witch, Raycast) handles the case.
// Requires Accessibility permission (TCC kTCCServiceAccessibility).
//
// Public surface is intentionally tiny — AppleScriptHelper.runJumpByUUID calls
// `raise(itermPID:windowID:title:)` after a successful AppleScript jump. No API
// change to ITerm2Jumper.
import AppKit
import ApplicationServices
import os

/// Private (but stable since 10.6) AX→CGWindowID bridge. Used by AltTab, yabai,
/// Rectangle, etc. Maps an AXUIElement window to its kCGWindow window number,
/// which equals NSWindow.windowNumber (and iTerm2's AppleScript `id of window`).
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AccessibilityRaiser {
    private static let log = Logger(subsystem: "com.claudealert.bot.hook", category: "ax")

    /// True iff this app is in the TCC Accessibility allow-list.
    static func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Diagnostic — emits the current AX trust state plus the running binary path
    /// so logs can confirm whether a "permission granted" UI toggle actually maps
    /// to this binary's cdhash. Ad-hoc builds change cdhash on every rebuild and
    /// silently invalidate TCC entries from prior builds.
    static func logTrustDiagnostics() {
        let trusted = AXIsProcessTrusted()
        let exe = Bundle.main.executablePath ?? "<unknown>"
        log.notice("[ax-trust trusted=\(trusted, privacy: .public) exe=\(exe, privacy: .public)]")
    }

    /// Triggers the system "Add to Accessibility" dialog if we are not yet trusted.
    /// macOS shows the dialog at most once per app install; subsequent calls while
    /// untrusted silently return false. After the user grants, the app must be
    /// relaunched for the new trust state to take effect.
    @discardableResult
    static func requestTrust() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Raise the iTerm2 window matching `windowID`, or `title` only when no ID is available.
    /// Returns true if a raise action was performed. Silently returns false if AX
    /// permission is not granted or no matching window is found.
    static func raise(itermPID: pid_t, windowID: CGWindowID?, title: String?) -> Bool {
        guard isTrusted() else {
            log.notice("[ax-skip reason=not-trusted]")
            return false
        }
        let appElement = AXUIElementCreateApplication(itermPID)
        var windowsRef: CFTypeRef?
        let copyErr = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef)
        guard copyErr == .success else {
            log.warning("[ax-error reason=copy-windows code=\(copyErr.rawValue, privacy: .public)]")
            return false
        }
        let fallbackAXWindows = fallbackWindows(appElement)
        var axWindows = (windowsRef as? [AXUIElement]) ?? []
        axWindows.append(contentsOf: fallbackAXWindows)

        guard let win = matchWindow(axWindows, windowID: windowID, title: title) else {
            // Emit available AX titles + CGWindowIDs when match fails so the user-side
            // log shows exactly why the title didn't line up (decoration drift between
            // iTerm AS `name of w` and AX kAXTitleAttribute is the likely cause).
            let available = axWindows.map { w -> String in
                var t: CFTypeRef?
                _ = AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &t)
                var cgID: CGWindowID = 0
                _ = _AXUIElementGetWindow(w, &cgID)
                let title = (t as? String) ?? "<nil>"
                return "\(cgID):\(title)"
            }.joined(separator: " || ")
            log.notice("[ax-miss windowID=\(windowID ?? 0, privacy: .public) title=\(title ?? "", privacy: .public) available=\(available, privacy: .public)]")
            return false
        }

        // Order matters on multi-display setups: activate() FIRST so macOS picks
        // *some* iTerm2 window as foreground (often the one on the active screen),
        // THEN raise + kAXMain + kAXFocused on the exact target so our raise is
        // the final state. Reversed order lets activate() overwrite the raise.
        // kAXRaiseAction is the only AX call that crosses Mission Control Spaces.
        if let app = NSRunningApplication(processIdentifier: itermPID) {
            app.activate()
        }
        let raiseErr = AXUIElementPerformAction(win, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(win, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        log.notice("[ax-raised windowID=\(windowID ?? 0, privacy: .public) code=\(raiseErr.rawValue, privacy: .public)]")
        return true
    }

    /// Look up the iTerm2 process PID. Returns nil if iTerm2 is not running.
    static func itermPID() -> pid_t? {
        NSWorkspace.shared.runningApplications
            .first(where: { $0.bundleIdentifier == "com.googlecode.iterm2" })?
            .processIdentifier
    }

    // MARK: - private

    private static func matchWindow(_ axWindows: [AXUIElement], windowID: CGWindowID?, title: String?) -> AXUIElement? {
        // 1) CGWindowID match — primary path. NSWindow.windowNumber == iTerm AS `id of w`.
        if let wantedID = windowID {
            for w in axWindows {
                var cgID: CGWindowID = 0
                if _AXUIElementGetWindow(w, &cgID) == .success, cgID == wantedID {
                    log.notice("[ax-match path=windowID id=\(wantedID, privacy: .public)]")
                    return w
                }
            }
        }
        // 2) Title match is only safe for legacy payloads without a window ID.
        //    When an ID was supplied, a duplicate title could select another Space.
        if windowID == nil, let wantedTitle = title, !wantedTitle.isEmpty {
            for w in axWindows {
                var titleRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(w, kAXTitleAttribute as CFString, &titleRef) == .success,
                   let t = titleRef as? String, t == wantedTitle {
                    log.notice("[ax-match path=title-fallback title=\(wantedTitle, privacy: .public)]")
                    return w
                }
            }
        }
        return nil
    }

    private static func fallbackWindows(_ appElement: AXUIElement) -> [AXUIElement] {
        [kAXFocusedWindowAttribute as CFString, kAXMainWindowAttribute as CFString].compactMap { attribute in
            var windowRef: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, attribute, &windowRef) == .success else {
                return nil
            }
            guard let windowRef else {
                return nil
            }
            return (windowRef as! AXUIElement)
        }
    }
}

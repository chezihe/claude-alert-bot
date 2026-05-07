// App/main.swift — pure-AppKit headless entry (RESEARCH Pattern 3).
// LSUIElement=true in Info.plist suppresses Dock/menu-bar/Cmd-Tab; .accessory belt-and-suspenders.
// No NSApp.activate — Phase 1 app is invisible by contract (DIST-05, RESEARCH Anti-Patterns).
import AppKit

let delegate = AppDelegate()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()

// App/main.swift — Phase 1 placeholder. Plan 03 wires up AppDelegate + HookListener.
import AppKit

// Headless entry point. LSUIElement=true in Info.plist suppresses Dock/menu-bar/Cmd-Tab.
// Plan 03 will introduce AppDelegate with NWListener lifecycle.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.run()

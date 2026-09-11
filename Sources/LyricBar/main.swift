import AppKit

// Entry point.
//   LyricBar                      -> menu bar app
//   LyricBar --probe T A [dur]    -> lyrics pipeline only (debugging)
let arguments = CommandLine.arguments
if arguments.count > 1, arguments[1] == "--probe" {
    Probe.run(Array(arguments.dropFirst(2)))
}

// Top-level code is not main-actor isolated unless it awaits, so hop explicitly.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}

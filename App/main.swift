import AppKit

// Programmatic entry point: no storyboard, no nib.
// The delegate is kept in a global because NSApplication.delegate is weak.
let appDelegate = AppDelegate()
let application = NSApplication.shared
application.delegate = appDelegate
application.setActivationPolicy(.regular)
application.run()

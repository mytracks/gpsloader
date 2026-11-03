import Foundation

// RosettaInstaller is built for x86_64 only (design.md D6).
//
// gpsloader opens this app via NSWorkspace when Rosetta is missing on Apple silicon.
// Launching an Intel-only app makes macOS show its own "install Rosetta" dialog.
// When Rosetta is present, the app starts and quits immediately.
exit(0)

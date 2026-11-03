import AppKit

/// About window with version, copyright and the license notices for gpsbabel and Qt
/// (spec `app-shell`, "Lizenzhinweise").
@MainActor
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    /// Where the corresponding source code is available.
    /// The copy on the developer's website is still open (design.md, Open Questions); until then these
    /// point to the upstream archives of exactly the bundled versions.
    enum SourceCode {
        static let gpsbabel = URL(string: "https://github.com/GPSBabel/gpsbabel/releases/tag/gpsbabel_1_7_0")!
        static let qt = URL(string: "https://download.qt.io/archive/qt/5.12/5.12.9/single/")!
    }

    private convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = String(localized: "About gpsloader")
        self.init(window: window)
        buildContent()
        window.center()
    }

    private func buildContent() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let copyright = info["NSHumanReadableCopyright"] as? String ?? ""

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let name = NSTextField(labelWithString: "gpsloader")
        name.font = .boldSystemFont(ofSize: 18)
        let versionLabel = NSTextField(labelWithString: String(localized: "Version \(version) (\(build))"))
        let copyrightLabel = NSTextField(labelWithString: copyright)
        copyrightLabel.textColor = .secondaryLabelColor

        let licenseTitle = NSTextField(labelWithString: String(localized: "Third-party software"))
        licenseTitle.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        let notice = NSTextField(wrappingLabelWithString: String(localized: """
        gpsloader includes GPSBabel 1.7.0 (copyright the GPSBabel authors), distributed under the GNU General Public \
        License version 2 or later. GPSBabel runs as a separate program and uses Qt Core 5.12.9 (copyright The Qt \
        Company Ltd. and other contributors), distributed under the GNU Lesser General Public License version 3. \
        The complete source code of both is available at the links below.
        """))
        notice.isSelectable = true

        let licenseButtons = NSStackView(views: [
            linkButton(String(localized: "GPL 2.0"), action: #selector(openGPL2(_:))),
            linkButton(String(localized: "LGPL 3.0"), action: #selector(openLGPL3(_:))),
            linkButton(String(localized: "GPL 3.0"), action: #selector(openGPL3(_:))),
        ])
        let sourceButtons = NSStackView(views: [
            linkButton(String(localized: "GPSBabel 1.7.0 source code"), action: #selector(openGPSBabelSource(_:))),
            linkButton(String(localized: "Qt 5.12.9 source code"), action: #selector(openQtSource(_:))),
        ])

        let stack = NSStackView(views: [icon, name, versionLabel, copyrightLabel, licenseTitle, notice,
                                        licenseButtons, sourceButtons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(20, after: copyrightLabel)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 24, right: 24)
        notice.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        window?.contentView = stack
    }

    private func linkButton(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .inline
        return button
    }

    /// URL of a bundled license text (`Contents/Resources/Licenses`).
    static func licenseURL(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "txt", subdirectory: "Licenses")
    }

    private func openLicense(_ name: String) {
        if let url = Self.licenseURL(name) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openGPL2(_ sender: Any?) { openLicense("GPL-2.0") }
    @objc private func openLGPL3(_ sender: Any?) { openLicense("LGPL-3.0") }
    @objc private func openGPL3(_ sender: Any?) { openLicense("GPL-3.0") }
    @objc private func openGPSBabelSource(_ sender: Any?) { NSWorkspace.shared.open(SourceCode.gpsbabel) }
    @objc private func openQtSource(_ sender: Any?) { NSWorkspace.shared.open(SourceCode.qt) }
}

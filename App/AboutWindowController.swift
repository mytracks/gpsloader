import AppKit
import FileConversion

/// About window with version, copyright, the app's license (GPL-3.0-or-later) and the notices for
/// GPSLoggerKit and the sources of ported formats and drivers (spec `app-shell`, "Lizenzhinweise").
@MainActor
final class AboutWindowController: NSWindowController {
    static let shared = AboutWindowController()

    /// Where the corresponding source code is available.
    enum SourceCode {
        /// Source code of the app itself (Info.plist `GPSLoaderSourceCodeURL`, build setting
        /// `GPSLOADER_SOURCE_CODE_URL`); `nil` while it is not set.
        static var app: URL? {
            guard let text = Bundle.main.object(forInfoDictionaryKey: "GPSLoaderSourceCodeURL") as? String,
                  text.hasPrefix("https://") else { return nil }
            return URL(string: text)
        }

        /// Repository of GPSLoggerKit (own repository since change split-repositories).
        static let gpsLoggerKit = URL(string: "https://github.com/mytracks/GPSLoggerKit")!
    }

    private convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 440),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = String(localized: "About \(AppName.current)")
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
        let name = NSTextField(labelWithString: AppName.current)
        name.font = .boldSystemFont(ofSize: 18)
        let versionLabel = NSTextField(labelWithString: String(localized: "Version \(version) (\(build))"))
        let copyrightLabel = NSTextField(labelWithString: copyright)
        copyrightLabel.textColor = .secondaryLabelColor

        let appLicenseTitle = title(String(localized: "License"))
        let appLicense = wrappingLabel(String(localized: """
        myTracks Loader is free software, distributed under the GNU General Public License version 3 or later. \
        You may redistribute and modify it under the terms of that license.
        """))
        var appLicenseViews = [linkButton(String(localized: "GPL 3.0"), action: #selector(openGPL3(_:)))]
        if SourceCode.app != nil {
            appLicenseViews.append(linkButton(String(localized: "Source code of myTracks Loader"), action: #selector(openAppSource(_:))))
        }
        let appLicenseButtons = NSStackView(views: appLicenseViews)

        let licenseTitle = title(String(localized: "Third-party software"))
        let kitNotice = wrappingLabel(String(localized: """
        myTracks Loader contains GPSLoggerKit (copyright 2026 Dirk Stichling), distributed under the MIT License. \
        Its source code is available in its own repository.
        """))
        let kitButtons = NSStackView(views: [linkButton(String(localized: "MIT License"), action: #selector(openMIT(_:))),
                                             linkButton(String(localized: "Source code of GPSLoggerKit"), action: #selector(openKitSource(_:)))])
        var views: [NSView] = [icon, name, versionLabel, copyrightLabel, appLicenseTitle, appLicense, appLicenseButtons,
                               licenseTitle, kitNotice, kitButtons]
        var wrapping = [appLicense, kitNotice]
        if !credits.isEmpty {
            let creditsNotice = wrappingLabel(String(localized: "Some file formats and device drivers are based on the source code of these projects:"))
            views += [title(String(localized: "Ported formats and drivers")), creditsNotice]
            wrapping.append(creditsNotice)
            for (index, credit) in credits.enumerated() {
                // The text wraps at the window width; the button gets its own row below it.
                let line = wrappingLabel("\(credit.project) – \(credit.authors) – \(credit.license)")
                line.isSelectable = true
                let button = linkButton(String(localized: "Source code"), action: #selector(openCreditSource(_:)))
                button.tag = index
                views += [line, NSStackView(views: [button])]
                wrapping.append(line)
            }
        }

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.setCustomSpacing(20, after: copyrightLabel)
        stack.setCustomSpacing(20, after: appLicenseButtons)
        stack.setCustomSpacing(20, after: kitButtons)
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 24, right: 24)
        for label in wrapping {
            label.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        }
        stack.widthAnchor.constraint(equalToConstant: 520).isActive = true
        window?.contentView = stack
        window?.setContentSize(stack.fittingSize)
    }

    /// One source of ported formats as shown in the window.
    struct CreditLine {
        var project: String
        var authors: String
        var license: String
        var sourceURL: URL
    }

    /// Sources of ported formats (GPSLoggerKitGPL); empty while there are none. Debug builds can add a line
    /// for snapshots with the default `DebugCredit` = "project|authors|license|url".
    private let credits: [CreditLine] = {
        var lines = AppFormats.credits.map {
            CreditLine(project: $0.project, authors: $0.authors, license: $0.license, sourceURL: $0.sourceURL)
        }
        #if DEBUG
        let parts = UserDefaults.standard.string(forKey: "DebugCredit")?.split(separator: "|").map(String.init) ?? []
        if parts.count == 4, let url = URL(string: parts[3]) {
            lines.append(CreditLine(project: parts[0], authors: parts[1], license: parts[2], sourceURL: url))
        }
        #endif
        return lines
    }()

    private func title(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        return label
    }

    private func wrappingLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.isSelectable = true
        return label
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

    @objc private func openGPL3(_ sender: Any?) { openLicense("GPL-3.0") }
    @objc private func openMIT(_ sender: Any?) { openLicense("MIT-GPSLoggerKit") }

    @objc private func openAppSource(_ sender: Any?) {
        if let url = SourceCode.app { NSWorkspace.shared.open(url) }
    }

    @objc private func openKitSource(_ sender: Any?) { NSWorkspace.shared.open(SourceCode.gpsLoggerKit) }

    @objc private func openCreditSource(_ sender: NSButton) {
        guard credits.indices.contains(sender.tag) else { return }
        NSWorkspace.shared.open(credits[sender.tag].sourceURL)
    }
}

import DiagnosticCapture
import Darwin
import Foundation
import LoggerCore
import SerialTransport

/// System and app facts for the support package (spec `support-package`, "Inhalt des Support-Pakets").
public struct SystemReport: Sendable, Equatable {
    public var appVersion: String
    public var build: String
    public var osVersion: String
    public var model: String
    public var architecture: String
    public var isTranslated: Bool
    public var languages: [String]
    public var timeZone: String

    public init(appVersion: String, build: String, osVersion: String, model: String, architecture: String,
                isTranslated: Bool, languages: [String], timeZone: String) {
        self.appVersion = appVersion
        self.build = build
        self.osVersion = osVersion
        self.model = model
        self.architecture = architecture
        self.isTranslated = isTranslated
        self.languages = languages
        self.timeZone = timeZone
    }

    public static func current(appVersion: String, build: String) -> SystemReport {
        let environment = CaptureEnvironment.current(appVersion: appVersion)
        return SystemReport(appVersion: appVersion, build: build, osVersion: environment.osVersion,
                            model: sysctlString("hw.model") ?? "unknown", architecture: environment.architecture,
                            isTranslated: environment.isTranslated, languages: Locale.preferredLanguages,
                            timeZone: TimeZone.current.identifier)
    }

    public var text: String {
        """
        \(ProductName.name) \(appVersion) (\(build))
        macOS: \(osVersion)
        Mac model: \(model)
        Architecture: \(architecture)\(isTranslated ? " (Rosetta)" : "")
        Languages: \(languages.joined(separator: ", "))
        Time zone: \(timeZone)

        """
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }
}

/// Text and file parts of the support package.
public enum SupportText {
    /// Serial ports and USB devices as a readable list.
    public static func portsAndUSB(ports: [SerialPortInfo], usb: [USBDeviceInfo]) -> String {
        func hex(_ value: Int?) -> String { value.map { String(format: "0x%04X", $0) } ?? "-" }
        var lines = ["Serial ports (\(ports.count)):"]
        for port in ports {
            var line = "  \(port.path)"
            if port.isUSB {
                line += "  USB \(hex(port.usbVendorID)):\(hex(port.usbProductID))"
                let names = [port.usbVendorName, port.usbProductName].compactMap { $0 }
                if !names.isEmpty { line += "  " + names.joined(separator: " / ") }
            }
            lines.append(line)
        }
        lines.append("")
        lines.append("USB devices (\(usb.count)):")
        for device in usb {
            var line = "  \(hex(device.vendorID)):\(hex(device.productID))"
            let names = [device.vendorName, device.productName].compactMap { $0 }
            if !names.isEmpty { line += "  " + names.joined(separator: " / ") }
            if let location = device.locationID { line += String(format: "  location 0x%08X", location) }
            lines.append(line)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The app's user defaults as an XML property list; `nil` if there are none.
    public static func settings(_ domain: [String: Any]?) -> Data? {
        guard let domain, !domain.isEmpty else { return nil }
        return try? PropertyListSerialization.data(fromPropertyList: domain, format: .xml, options: 0)
    }
}

/// Crash reports of the app written by macOS, also those from the time it was called gpsloader.
public enum CrashReports {
    /// `~/Library/Logs/DiagnosticReports` and its `Retired` folder.
    public static var defaultDirectories: [URL] {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let reports = library.appendingPathComponent("Logs/DiagnosticReports", isDirectory: true)
        return [reports, reports.appendingPathComponent("Retired", isDirectory: true)]
    }

    /// Whether a report file name belongs to the app: macOS names reports after the process, which was
    /// "gpsloader" in earlier builds.
    static func isCrashReportName(_ name: String) -> Bool {
        name.hasPrefix(ProductName.name) || name.hasPrefix(ProductName.legacyName)
    }

    /// Reports whose name starts with "myTracks Loader" or "gpsloader", newest first, at most `limit`.
    public static func find(in directories: [URL] = defaultDirectories, limit: Int = 10) -> [URL] {
        let manager = FileManager.default
        let reports = directories.flatMap { directory -> [URL] in
            let urls = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            return urls.filter { isCrashReportName($0.lastPathComponent) && ["ips", "crash", "diag", "hang"].contains($0.pathExtension) }
        }
        func modified(_ url: URL) -> Date {
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
        return Array(reports.sorted { modified($0) > modified($1) }.prefix(limit))
    }
}

import DiagnosticCapture
import Foundation
import LoggerCore
import SerialTransport

/// The parts a user can choose for a support package (spec `support-package`, "Inhalt des Support-Pakets").
public enum SupportPackageItem: String, Sendable, CaseIterable, Hashable {
    case system, log, settings, ports, bluetooth, captures, crashReports
}

/// Where the parts of a support package come from; tests replace them with fixed content.
public struct SupportPackageSources: Sendable {
    public var appVersion: String
    public var system: @Sendable () -> String
    public var logFiles: @Sendable () -> [URL]
    public var settings: @Sendable () -> Data?
    public var portsAndUSB: @Sendable () -> String
    /// The paired Bluetooth devices as text; `nil` when not available (no Bluetooth permission).
    public var bluetooth: String?
    public var captures: @Sendable () -> [URL]
    public var crashReports: @Sendable () -> [URL]

    public init(appVersion: String, system: @escaping @Sendable () -> String, logFiles: @escaping @Sendable () -> [URL],
                settings: @escaping @Sendable () -> Data?, portsAndUSB: @escaping @Sendable () -> String, bluetooth: String?,
                captures: @escaping @Sendable () -> [URL], crashReports: @escaping @Sendable () -> [URL]) {
        self.appVersion = appVersion
        self.system = system
        self.logFiles = logFiles
        self.settings = settings
        self.portsAndUSB = portsAndUSB
        self.bluetooth = bluetooth
        self.captures = captures
        self.crashReports = crashReports
    }

    /// The real sources of the running app.
    public static func standard(appVersion: String, build: String, bundleIdentifier: String?, log: AppLog,
                                captureStore: CaptureStore, bluetooth: String?) -> SupportPackageSources {
        SupportPackageSources(
            appVersion: appVersion,
            system: { SystemReport.current(appVersion: appVersion, build: build).text },
            logFiles: { log.files },
            settings: { SupportText.settings(bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }) },
            portsAndUSB: { SupportText.portsAndUSB(ports: SerialPortCatalog.currentPorts(), usb: USBDeviceCatalog.currentDevices()) },
            bluetooth: bluetooth,
            captures: { captureStore.captures() },
            crashReports: { CrashReports.find() })
    }
}

/// Writes the chosen parts into a folder and zips it (design D4: `NSFileCoordinator` with `.forUploading`).
public enum SupportPackageBuilder {
    /// "myTracks-Loader-Support-20261114-1030" in local time.
    public static func baseName(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "\(ProductName.fileStem)-Support-%04d%02d%02d-%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0,
                      c.hour ?? 0, c.minute ?? 0)
    }

    public static func suggestedFileName(for date: Date) -> String {
        baseName(for: date) + ".zip"
    }

    /// Builds the package and writes the ZIP to `destination` (replacing an existing file).
    /// - Throws: `LoggerError(.writeFailed)` with the reason.
    public static func build(items: Set<SupportPackageItem>, sources: SupportPackageSources, to destination: URL,
                             date: Date = Date()) async throws {
        let manager = FileManager.default
        let work = manager.temporaryDirectory.appendingPathComponent("\(ProductName.fileStem)-Support-\(UUID().uuidString)", isDirectory: true)
        let folder = work.appendingPathComponent(baseName(for: date), isDirectory: true)
        defer { try? manager.removeItem(at: work) }
        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            let contents = try writeParts(items: items, sources: sources, into: folder)
            try readme(date: date, appVersion: sources.appVersion, contents: contents)
                .write(to: folder.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
            try zip(folder, to: destination)
        } catch let error as LoggerError {
            throw error
        } catch {
            throw LoggerError(.writeFailed, detail: error.localizedDescription)
        }
    }

    /// Writes the parts; returns one line per written part for the README.
    static func writeParts(items: Set<SupportPackageItem>, sources: SupportPackageSources, into folder: URL) throws -> [String] {
        var contents: [String] = []
        func write(_ text: String, _ name: String) throws {
            try text.write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        func copy(_ urls: [URL], into name: String) throws -> Int {
            guard !urls.isEmpty else { return 0 }
            let target = folder.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            for url in urls {
                try FileManager.default.copyItem(at: url, to: target.appendingPathComponent(url.lastPathComponent))
            }
            return urls.count
        }
        if items.contains(.system) {
            try write(sources.system(), "system.txt")
            contents.append("system.txt – app, macOS, Mac model, architecture, languages, time zone")
        }
        if items.contains(.log) {
            let count = try copy(sources.logFiles(), into: "log")
            contents.append("log/ – app log (\(count) files)")
        }
        if items.contains(.settings), let settings = sources.settings() {
            try settings.write(to: folder.appendingPathComponent("settings.plist"))
            contents.append("settings.plist – settings of the app")
        }
        if items.contains(.ports) {
            try write(sources.portsAndUSB(), "ports-and-usb.txt")
            contents.append("ports-and-usb.txt – serial ports and USB devices (no serial numbers)")
        }
        if items.contains(.bluetooth), let bluetooth = sources.bluetooth {
            try write(bluetooth, "bluetooth.txt")
            contents.append("bluetooth.txt – paired Bluetooth devices")
        }
        if items.contains(.captures) {
            let count = try copy(sources.captures(), into: "captures")
            contents.append("captures/ – diagnostic captures of the last operations (\(count) files, contain positions)")
        }
        if items.contains(.crashReports) {
            let count = try copy(sources.crashReports(), into: "crash-reports")
            contents.append("crash-reports/ – crash reports of \(ProductName.name) (\(count) files)")
        }
        return contents
    }

    static func readme(date: Date, appVersion: String, contents: [String]) -> String {
        let time = date.formatted(Date.ISO8601FormatStyle(timeZone: .current))
        return """
        \(ProductName.name) support package
        Created: \(time)
        App version: \(appVersion)

        Contents:
        \(contents.map { "- " + $0 }.joined(separator: "\n"))

        This package was saved by the user and is not sent anywhere by \(ProductName.name).

        """
    }

    /// Lets Foundation zip the folder (`.forUploading`) and copies the archive to `destination`.
    static func zip(_ folder: URL, to destination: URL) throws {
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipURL in
            do {
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: zipURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError { throw error }
    }
}

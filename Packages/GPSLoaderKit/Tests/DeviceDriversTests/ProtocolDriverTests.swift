import Foundation
import Testing
import GPSLoggerKit
import GPSLoggerKitGPL
import LoggerCore
import SerialTransport
import TestSupport
@testable import DeviceDrivers

/// Collects diagnostic events.
final class EventLog: DiagnosticSink, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [DiagnosticEvent] = []
    func record(_ event: DiagnosticEvent) { lock.lock(); storage.append(event); lock.unlock() }
    var events: [DiagnosticEvent] { lock.lock(); defer { lock.unlock() }; return storage }
}

/// Sends "HELLO\r\n", expects "50.0,8.0\r\n" and "END\r\n"; a "?" answer is a protocol error.
private struct HelloProtocol: DeviceProtocol {
    var eraseSupport: DeviceErase { .supported }

    func read(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws -> Recording {
        reporter.step("Connecting")
        try await connection.setBaudRate(115_200)
        try await connection.write(Array("HELLO\r\n".utf8))
        let line = String(decoding: try await connection.readUntil([0x0D, 0x0A], maxLength: 100, timeout: 1), as: UTF8.self)
        guard line != "?" else { throw DeviceProtocolError("Unexpected answer: ?") }
        let values = line.split(separator: ",").compactMap { Double($0) }
        reporter.progress(1, of: 1)
        _ = try await connection.readUntil([0x0D, 0x0A], maxLength: 100, timeout: 1)
        return Recording(tracks: [Track(segments: [TrackSegment(points: [TrackPoint(latitude: values[0], longitude: values[1])])])])
    }

    func erase(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws {
        try await connection.write(Array("ERASE\r\n".utf8))
    }
}

private func entry() -> DeviceEntry {
    DeviceEntry(id: "test.hello", name: "Hello Logger", driverID: "hello", connection: .serial(baudRate: 9600)) {
        HelloProtocol()
    }
}

private func driver(_ mock: MockTransport) -> ProtocolDriver {
    ProtocolDriver(entry: entry(), portPath: "/dev/cu.mock", hidFactory: nil) { _, _ in mock }
}

@Suite("Protocol driver adapter")
struct ProtocolDriverTests {
    /// Scenario "Mitschnitt" plus progress and closing.
    @Test func readsAndCaptures() async throws {
        let mock = MockTransport(script: [.expect("HELLO\r\n"), .reply("50.0,8.0\r\nEND\r\n")])
        let log = EventLog()
        let progress = ProgressLog()
        let context = DriverContext(progress: { progress.add($0) }, diagnostics: log)
        let recording = try await driver(mock).read(context)
        #expect(recording.trackPointCount == 1)
        #expect(await mock.closeCount == 1)
        #expect(log.events.contains(.transmitted(source: "/dev/cu.mock", bytes: Array("HELLO\r\n".utf8))))
        #expect(log.events.contains { if case .received = $0 { true } else { false } })
        #expect(progress.values.contains(.indeterminate(step: "Connecting")))
        #expect(progress.values.contains(.determinate(completed: 1, total: 1, step: nil)))
    }

    /// Scenario "Protokollfehler"; the transport is closed as well.
    @Test func protocolErrorIsMapped() async {
        let mock = MockTransport(script: [.expect("HELLO\r\n"), .reply("?\r\n")])
        await #expect(throws: LoggerError(.protocolError, detail: "Unexpected answer: ?")) {
            try await driver(mock).read(DriverContext())
        }
        #expect(await mock.closeCount == 1)
    }

    @Test func timeoutIsPassedOn() async {
        let mock = MockTransport(script: [.expect("HELLO\r\n")])
        await #expect(throws: LoggerError.self) {
            try await driver(mock).read(DriverContext())
        }
        #expect(await mock.closeCount == 1)
    }

    @Test func descriptorAndErase() async throws {
        let mock = MockTransport(script: [.expect("ERASE\r\n")])
        let d = driver(mock)
        #expect(d.descriptor.eraseSupport == .supported && d.descriptor.name == "Hello Logger")
        #expect(d.resourceKey == "/dev/cu.mock")
        try await d.erase(DriverContext())
        #expect(await mock.isScriptFinished)
    }

    @Test func serialEntryWithoutPort() async {
        let d = ProtocolDriver(entry: entry(), portPath: nil)
        await #expect(throws: LoggerError(.deviceNotFound, detail: "No port selected")) {
            try await d.read(DriverContext())
        }
        #expect(entry().needsPort)
    }

    /// Scenario "Treiber fehlt": the catalog lists only devices with a driver, sorted by name.
    @Test func catalogIsSorted() {
        let names = DeviceCatalog.entries.map(\.name)
        #expect(names == names.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(Set(DeviceCatalog.entries.map(\.id)).count == DeviceCatalog.entries.count)
    }
}

final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ProgressUpdate] = []
    func add(_ value: ProgressUpdate) { lock.lock(); storage.append(value); lock.unlock() }
    var values: [ProgressUpdate] { lock.lock(); defer { lock.unlock() }; return storage }
}

@Suite("Device selection")
struct DeviceSelectionTests {
    private let serial = DeviceEntry(id: "a.serial", name: "A", driverID: "a", connection: .serial(baudRate: 9600)) {
        HelloProtocol()
    }
    private let readOnly = DeviceEntry(id: "b.readonly", name: "B", driverID: "b", connection: .serial(baudRate: 9600)) {
        ReadOnlyProtocol()
    }
    private let hid = DeviceEntry(id: "c.hid", name: "C", driverID: "c", connection: .hid(vendorID: 1, productIDs: [2])) {
        HelloProtocol()
    }
    private let ports = [SerialPortInfo(path: "/dev/cu.Bluetooth-Incoming-Port"),
                         SerialPortInfo(path: "/dev/cu.usbserial-1410", usbVendorID: 0x067B, usbProductID: 0x2303)]

    /// Scenario "Auswahl merken".
    @Test func restoresTheStoredSelection() {
        let stored = DeviceSelection(stored: ["device": "b.readonly", "port": "/dev/cu.usbserial-1410"])
        let restored = DeviceSelection.restore(stored, entries: [serial, readOnly], ports: ports)
        #expect(restored == DeviceSelection(entryID: "b.readonly", portPath: "/dev/cu.usbserial-1410"))
        #expect(DeviceSelection(stored: restored.stored) == restored)
        let gone = DeviceSelection.restore(DeviceSelection(entryID: "x", portPath: "/dev/cu.gone"), entries: [serial], ports: ports)
        #expect(gone == DeviceSelection(entryID: "a.serial", portPath: "/dev/cu.usbserial-1410"))
    }

    /// Scenario "Logger angesteckt".
    @Test func newPortIsPickedUp() {
        #expect(DeviceSelection.port(preferring: nil, in: []) == nil)
        #expect(DeviceSelection.port(preferring: nil, in: ports) == "/dev/cu.usbserial-1410")
        #expect(DeviceSelection.port(preferring: "/dev/cu.Bluetooth-Incoming-Port", in: ports) == "/dev/cu.Bluetooth-Incoming-Port")
    }

    /// Scenarios "Kein Anschluss" and "Gerät ohne Löschfunktion".
    @Test func availability() {
        let entries = [serial, readOnly, hid]
        let noPort = DeviceSelection(entryID: "a.serial", portPath: nil)
        #expect(!noPort.canRead(entries: entries, isRunning: false))
        #expect(noPort.hint(entries: entries) == .noPort)
        let withPort = DeviceSelection(entryID: "a.serial", portPath: "/dev/cu.usbserial-1410")
        #expect(withPort.canRead(entries: entries, isRunning: false) && withPort.canErase(entries: entries, isRunning: false))
        #expect(!withPort.canRead(entries: entries, isRunning: true))
        let readOnlySelection = DeviceSelection(entryID: "b.readonly", portPath: "/dev/cu.usbserial-1410")
        #expect(readOnlySelection.canRead(entries: entries, isRunning: false))
        #expect(!readOnlySelection.canErase(entries: entries, isRunning: false))
        let hidSelection = DeviceSelection(entryID: "c.hid", portPath: nil)
        #expect(hidSelection.canRead(entries: entries, isRunning: false) && hidSelection.hint(entries: entries) == nil)
    }
}

private struct ReadOnlyProtocol: DeviceProtocol {
    func read(_ connection: any DeviceConnection, _ reporter: DeviceReporter) async throws -> Recording { Recording() }
}

@Suite("Device catalog")
struct DeviceCatalogTests {
    /// Spec `skytraq-device`, "Geräte im Katalog".
    @Test func skyTraqDevices() throws {
        let skytraq = DeviceCatalog.entries.filter { $0.driverID == "skytraq" }
        #expect(skytraq.count == 11)
        let gt750 = try #require(DeviceCatalog.entry(withID: "skytraq.canmore-gt-750f"))
        #expect(gt750.connection == .serial(baudRate: 38400))
        let protocolValue = try #require(gt750.makeProtocol() as? SkyTraqDevice)
        #expect(protocolValue.initialBaudRate == 38400 && protocolValue.downloadBaudRate == 38400)
        let venus = try #require(DeviceCatalog.entry(withID: "skytraq.venus").map { $0.makeProtocol() as? SkyTraqDevice } ?? nil)
        #expect(venus.initialBaudRate == nil && venus.downloadBaudRate == 230_400)
        #expect(skytraq.allSatisfy { $0.eraseSupport == .supported })
    }
}

@Suite("Device catalog – MTK")
struct MTKCatalogTests {
    /// Spec `mtk-device`, "MTK-Geräte im Katalog".
    @Test func mtkDevices() throws {
        #expect(DeviceCatalog.entries.filter { $0.driverID == "mtk" }.count == 9)
        let holux = try #require(DeviceCatalog.entry(withID: "m241.holux-m-241"))
        #expect(holux.connection == .serial(baudRate: 38400))
        #expect(DeviceCatalog.entry(withID: "mtk.qstarz-bt-q1000")?.connection == .serial(baudRate: 115_200))
        #expect(DeviceCatalog.entries.filter { $0.driverID == "m241" }.allSatisfy { $0.eraseSupport == .supported })
    }
}

@Suite("Device catalog – Wintec")
struct WintecCatalogTests {
    /// Spec `wintec-device`, "Wintec-Geräte im Katalog".
    @Test func wintecDevices() {
        let wintec = DeviceCatalog.entries.filter { $0.driverID == "wbt" }
        #expect(wintec.count == 5)
        #expect(wintec.allSatisfy { $0.eraseSupport == .supported && $0.connection == .serial(baudRate: 9600) })
    }
}

@Suite("Device catalog – Navilink")
struct NavilinkCatalogTests {
    /// Spec `navilink-device`, "Navilink-Geräte im Katalog".
    @Test func navilinkDevices() {
        let navilink = DeviceCatalog.entries.filter { $0.driverID == "navilink" }
        #expect(navilink.count == 6)
        #expect(navilink.allSatisfy { $0.eraseSupport == .unsupported && $0.connection == .serial(baudRate: 115_200) })
    }
}

@Suite("Device catalog – Magellan")
struct MagellanCatalogTests {
    /// Spec `magellan-device`, "Magellan-Gerät wählen".
    @Test func magellanDevices() throws {
        let magellan = DeviceCatalog.entries.filter { $0.driverID == "magellan" }
        #expect(magellan.count == 7)
        #expect(magellan.allSatisfy { $0.eraseSupport == .unsupported && $0.connection == .serial(baudRate: 4800) })
        let sportrak = try #require(DeviceCatalog.entry(withID: "magellan.sportrak-map"))
        #expect(sportrak.name == "Magellan SporTrak Map")
        let selection = DeviceSelection(entryID: sportrak.id, portPath: "/dev/cu.usbserial")
        #expect(selection.canRead(entries: DeviceCatalog.entries, isRunning: false))
        #expect(!selection.canErase(entries: DeviceCatalog.entries, isRunning: false))
    }
}

@Suite("Device catalog – iTrackU")
struct ITrackUCatalogTests {
    /// Spec `itracku-device`, "iTrackU wählen".
    @Test func itrackuDevice() throws {
        let entry = try #require(DeviceCatalog.entry(withID: "itracku.xaiox-itracku"))
        #expect(entry.name == "XAiOX iTrackU" && entry.driverID == "itracku")
        #expect(entry.connection == .serial(baudRate: 4800) && entry.eraseSupport == .unsupported)
        let selection = DeviceSelection(entryID: entry.id, portPath: "/dev/cu.iTrackU")
        #expect(selection.canRead(entries: DeviceCatalog.entries, isRunning: false))
        #expect(!selection.canErase(entries: DeviceCatalog.entries, isRunning: false))
    }
}

@Suite("Device catalog – i-GotU")
struct IGotUCatalogTests {
    /// Spec `igotu-device`, "i-GotU-Geräte im Katalog".
    @Test func igotuDevices() {
        let igotu = DeviceCatalog.entries.filter { $0.driverID == "igotu" }
        #expect(igotu.count == 7)
        #expect(igotu.allSatisfy { $0.eraseSupport == .experimental })
        #expect(igotu.filter { !$0.needsPort }.count == 5)
        #expect(DeviceCatalog.entry(withID: "igotu.gt-800")?.connection == .serial(baudRate: 9600))
    }
}

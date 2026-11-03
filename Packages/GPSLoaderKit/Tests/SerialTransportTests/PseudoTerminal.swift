import Darwin
import Foundation

/// A pseudo terminal pair for testing serial code without hardware.
/// The "device" side is the master; the code under test opens `path` (the slave).
final class PseudoTerminal {
    let masterFD: Int32
    private var slaveFD: Int32
    let path: String

    init() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var name = [CChar](repeating: 0, count: 128)
        guard openpty(&master, &slave, &name, nil, nil) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        masterFD = master
        slaveFD = slave
        path = String(decoding: name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        // Raw mode on the master side so bytes are passed through unchanged.
        var attributes = termios()
        tcgetattr(slave, &attributes)
        cfmakeraw(&attributes)
        tcsetattr(slave, TCSANOW, &attributes)
    }

    /// Closes the slave descriptor held by the test itself, so that only the code under test keeps it open.
    func releaseSlave() {
        if slaveFD >= 0 {
            close(slaveFD)
            slaveFD = -1
        }
    }

    /// Current terminal attributes as seen by the code under test.
    func slaveAttributes() -> termios {
        let fd = open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        defer { if fd >= 0 { close(fd) } }
        var attributes = termios()
        tcgetattr(fd, &attributes)
        return attributes
    }

    /// Simulates the device sending bytes.
    func deviceSend(_ bytes: [UInt8]) {
        bytes.withUnsafeBytes { buffer in
            _ = write(masterFD, buffer.baseAddress, buffer.count)
        }
    }

    func deviceSend(_ string: String) {
        deviceSend(Array(string.utf8))
    }

    /// Reads what the code under test has written to the device (waits up to `timeout`).
    func deviceReceive(count: Int, timeout: TimeInterval = 2) -> [UInt8] {
        var result: [UInt8] = []
        let deadline = Date().addingTimeInterval(timeout)
        while result.count < count, Date() < deadline {
            var pfd = pollfd(fd: masterFD, events: Int16(POLLIN), revents: 0)
            guard poll(&pfd, 1, 50) > 0 else { continue }
            var buffer = [UInt8](repeating: 0, count: count - result.count)
            let n = read(masterFD, &buffer, buffer.count)
            if n > 0 { result.append(contentsOf: buffer.prefix(n)) }
        }
        return result
    }

    /// Simulates unplugging the device.
    func hangUp() {
        close(masterFD)
    }

    deinit {
        releaseSlave()
        close(masterFD)
    }
}

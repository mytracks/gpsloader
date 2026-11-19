import Darwin
import Foundation
import LoggerCore

/// A serial port (`/dev/cu.*`) as `ByteTransport` (spec `serial-transport`).
///
/// - Opened exclusively (`TIOCEXCL` plus `flock`), raw mode, 8N1, no flow control.
/// - Reads wait with `poll()` on a private dispatch queue in steps of 100 ms, so no thread of
///   the Swift concurrency pool blocks and cancellation takes effect within 100 ms.
/// - On cancellation, hang-up or I/O errors the port closes itself, so it is released in every case.
public actor SerialPort: ByteTransport {
    /// Baud rates the port accepts.
    public static let supportedBaudRates: Set<Int> = [1200, 2400, 4800, 9600, 19200, 38400, 57600, 115200, 230400]

    public nonisolated let identifier: String
    public private(set) var baudRate: Int

    private var fd: Int32 = -1
    private var pending: [UInt8] = []
    private let ioQueue: DispatchQueue

    public init(path: String, baudRate: Int) {
        self.identifier = path
        self.baudRate = baudRate
        self.ioQueue = DispatchQueue(label: "gpsloader.serial.\(path)")
    }

    deinit {
        if fd >= 0 {
            Darwin.close(fd)
        }
    }

    public var isOpen: Bool { fd >= 0 }

    // MARK: - Open / close

    public func open() async throws {
        guard fd < 0 else { return }
        guard Self.supportedBaudRates.contains(baudRate) else {
            throw LoggerError(.protocolError, detail: "Unsupported baud rate \(baudRate)")
        }

        let descriptor = Darwin.open(identifier, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw Self.openError(errno: errno, path: identifier)
        }

        if ioctl(descriptor, TIOCEXCL) != 0, errno == EBUSY {
            Darwin.close(descriptor)
            throw LoggerError(.portBusy, detail: identifier)
        }
        if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            let error = errno
            Darwin.close(descriptor)
            if error == EWOULDBLOCK {
                throw LoggerError(.portBusy, detail: identifier)
            }
            throw LoggerError(.deviceNotFound, detail: "\(identifier): flock: \(Self.describe(errno: error))")
        }

        var attributes = termios()
        guard tcgetattr(descriptor, &attributes) == 0 else {
            let error = errno
            Darwin.close(descriptor)
            throw LoggerError(.deviceNotFound, detail: "\(identifier): tcgetattr: \(Self.describe(errno: error))")
        }
        cfmakeraw(&attributes)
        attributes.c_cflag |= tcflag_t(CLOCAL | CREAD | CS8)
        attributes.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CRTSCTS)
        attributes.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)
        Self.setControlCharacter(&attributes, index: VMIN, value: 0)
        Self.setControlCharacter(&attributes, index: VTIME, value: 0)
        cfsetspeed(&attributes, speed_t(baudRate))
        guard tcsetattr(descriptor, TCSANOW, &attributes) == 0 else {
            let error = errno
            Darwin.close(descriptor)
            throw LoggerError(.deviceNotFound, detail: "\(identifier): tcsetattr: \(Self.describe(errno: error))")
        }
        tcflush(descriptor, TCIOFLUSH)

        fd = descriptor
        pending = []
    }

    public func close() async {
        closeDescriptor()
    }

    /// Switches the baud rate of the open port (spec `serial-transport`, "Change the baud rate").
    /// Output still queued is sent at the old rate first (`TCSADRAIN`).
    public func setBaudRate(_ rate: Int) async throws {
        guard Self.supportedBaudRates.contains(rate) else {
            throw LoggerError(.protocolError, detail: "Unsupported baud rate \(rate)")
        }
        let descriptor = try openDescriptor()
        var attributes = termios()
        guard tcgetattr(descriptor, &attributes) == 0 else {
            throw LoggerError(.protocolError, detail: "\(identifier): tcgetattr: \(Self.describe(errno: errno))")
        }
        cfsetspeed(&attributes, speed_t(rate))
        guard tcsetattr(descriptor, TCSADRAIN, &attributes) == 0 else {
            throw LoggerError(.protocolError, detail: "\(identifier): tcsetattr: \(Self.describe(errno: errno))")
        }
        baudRate = rate
    }

    /// Drops received bytes that were not read yet, including those buffered by the driver.
    public func discardInput() async {
        pending = []
        if fd >= 0 { tcflush(fd, TCIFLUSH) }
    }

    /// The speed currently configured on the open descriptor (for tests).
    public func configuredSpeed() -> Int? {
        guard fd >= 0 else { return nil }
        var attributes = termios()
        guard tcgetattr(fd, &attributes) == 0 else { return nil }
        return Int(cfgetospeed(&attributes))
    }

    private func closeDescriptor() {
        guard fd >= 0 else { return }
        Darwin.close(fd) // also releases the flock
        fd = -1
        pending = []
    }

    // MARK: - Writing

    public func write(_ bytes: [UInt8]) async throws {
        let descriptor = try openDescriptor()
        let cancelled = Locked(false)
        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    ioQueue.async {
                        continuation.resume(with: Result {
                            try Self.writeAll(bytes, to: descriptor, cancelled: cancelled, path: self.identifier)
                        })
                    }
                }
            } onCancel: {
                cancelled.withLock { $0 = true }
            }
        } catch let error as LoggerError where error.kind != .timeout {
            closeDescriptor()
            throw error
        }
    }

    // MARK: - Reading

    public func read(count: Int, timeout: TimeInterval) async throws -> [UInt8] {
        while pending.count < count {
            try await receiveChunk(timeout: timeout)
        }
        let result = Array(pending.prefix(count))
        pending.removeFirst(count)
        return result
    }

    public func readUntil(_ terminator: [UInt8], maxLength: Int, timeout: TimeInterval) async throws -> [UInt8] {
        precondition(!terminator.isEmpty, "terminator must not be empty")
        while true {
            if let range = pending.firstRange(of: terminator) {
                let line = Array(pending[..<range.lowerBound])
                pending.removeFirst(range.upperBound)
                return line
            }
            if pending.count >= maxLength {
                let head = Array(pending.prefix(maxLength))
                pending.removeFirst(maxLength)
                throw LoggerError(.protocolError,
                                  detail: "\(identifier): no terminator within \(maxLength) bytes: \(head.printableASCII)")
            }
            try await receiveChunk(timeout: timeout)
        }
    }

    /// Waits up to `timeout` for at least one byte and appends what arrived to `pending`.
    private func receiveChunk(timeout: TimeInterval) async throws {
        let descriptor = try openDescriptor()
        let cancelled = Locked(false)
        do {
            let chunk = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[UInt8], any Error>) in
                    ioQueue.async {
                        continuation.resume(with: Result {
                            try Self.readAvailable(from: descriptor, timeout: timeout, cancelled: cancelled, path: self.identifier)
                        })
                    }
                }
            } onCancel: {
                cancelled.withLock { $0 = true }
            }
            pending.append(contentsOf: chunk)
        } catch let error as LoggerError where error.kind != .timeout {
            // Cancelled, disconnected or broken: release the port.
            closeDescriptor()
            throw error
        }
    }

    private func openDescriptor() throws -> Int32 {
        if Task.isCancelled {
            closeDescriptor()
            throw LoggerError(.cancelled)
        }
        guard fd >= 0 else {
            throw LoggerError(.deviceNotFound, detail: "\(identifier) is not open")
        }
        return fd
    }

    // MARK: - Blocking helpers (run on ioQueue)

    private static let pollStepMilliseconds: Int32 = 100

    private static func readAvailable(from fd: Int32, timeout: TimeInterval, cancelled: Locked<Bool>,
                                      path: String) throws -> [UInt8] {
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            if cancelled.current { throw LoggerError(.cancelled) }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                throw LoggerError(.timeout, detail: "\(path): no data for \(timeout) s")
            }
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let wait = min(pollStepMilliseconds, Int32((remaining * 1000).rounded(.up)))
            let ready = poll(&pfd, 1, wait)
            if ready < 0 {
                if errno == EINTR { continue }
                throw LoggerError(.deviceNotFound, detail: "\(path): poll: \(describe(errno: errno))")
            }
            if ready == 0 { continue }

            if pfd.revents & Int16(POLLIN) != 0 {
                let n = Darwin.read(fd, &buffer, buffer.count)
                if n > 0 { return Array(buffer.prefix(n)) }
                if n == 0 { throw disconnected(path) }
                if errno == EAGAIN || errno == EINTR { continue }
                throw LoggerError(.deviceNotFound, detail: "\(path): read: \(describe(errno: errno))")
            }
            if pfd.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 {
                throw disconnected(path)
            }
        }
    }

    private static func writeAll(_ bytes: [UInt8], to fd: Int32, cancelled: Locked<Bool>, path: String) throws {
        var offset = 0
        while offset < bytes.count {
            if cancelled.current { throw LoggerError(.cancelled) }
            let n = bytes[offset...].withUnsafeBytes { Darwin.write(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                offset += n
                continue
            }
            if n < 0 && (errno == EAGAIN || errno == EINTR) {
                var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                _ = poll(&pfd, 1, pollStepMilliseconds)
                if pfd.revents & Int16(POLLHUP | POLLERR | POLLNVAL) != 0 { throw disconnected(path) }
                continue
            }
            throw LoggerError(.deviceNotFound, detail: "\(path): write: \(describe(errno: errno))")
        }
    }

    private static func disconnected(_ path: String) -> LoggerError {
        LoggerError(.deviceNotFound, detail: "\(path): device disconnected")
    }

    private static func openError(errno error: Int32, path: String) -> LoggerError {
        switch error {
        case EBUSY:
            LoggerError(.portBusy, detail: path)
        default:
            LoggerError(.deviceNotFound, detail: "\(path): \(describe(errno: error))")
        }
    }

    static func describe(errno error: Int32) -> String {
        String(cString: strerror(error))
    }

    private static func setControlCharacter(_ attributes: inout termios, index: Int32, value: cc_t) {
        withUnsafeMutableBytes(of: &attributes.c_cc) { buffer in
            buffer[Int(index)] = value
        }
    }
}

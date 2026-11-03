import Darwin
import Foundation
import IOKit
import IOKit.serial
import Testing

/// Feasibility checks for the system APIs the serial transport relies on (task 1.5).
@Suite("System boundaries")
struct SystemBoundaryTests {
    @Test func ioctlTermiosAndFlockWorkFromSwift() throws {
        let pty = try PseudoTerminal()
        let fd = open(pty.path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        #expect(fd >= 0)
        defer { close(fd) }

        #expect(ioctl(fd, TIOCEXCL) == 0)
        #expect(flock(fd, LOCK_EX | LOCK_NB) == 0)

        // A second descriptor must not get the lock.
        let fd2 = open(pty.path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        if fd2 >= 0 {
            defer { close(fd2) }
            #expect(flock(fd2, LOCK_EX | LOCK_NB) == -1)
            #expect(errno == EWOULDBLOCK)
        }

        var attributes = termios()
        #expect(tcgetattr(fd, &attributes) == 0)
        cfmakeraw(&attributes)
        attributes.c_cflag |= tcflag_t(CLOCAL | CREAD)
        #expect(cfsetspeed(&attributes, speed_t(B115200)) == 0)
        #expect(tcsetattr(fd, TCSANOW, &attributes) == 0)

        var readBack = termios()
        tcgetattr(fd, &readBack)
        #expect(cfgetospeed(&readBack) == speed_t(B115200))
    }

    @Test func ioKitSerialMatchingIsAvailable() {
        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOSerialBSDServiceValue), &iterator)
        #expect(result == KERN_SUCCESS)
        IOObjectRelease(iterator)
    }
}

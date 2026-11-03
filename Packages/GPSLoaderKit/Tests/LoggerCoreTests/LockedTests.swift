import Testing
@testable import LoggerCore

@Suite("Locked")
struct LockedTests {
    @Test func concurrentIncrementsAreNotLost() async {
        let counter = Locked(0)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<1000 {
                group.addTask {
                    counter.withLock { $0 += 1 }
                }
            }
        }
        #expect(counter.current == 1000)
    }

    @Test func withLockReturnsResult() {
        let box = Locked([1, 2, 3])
        let sum = box.withLock { values in values.reduce(0, +) }
        #expect(sum == 6)
    }
}

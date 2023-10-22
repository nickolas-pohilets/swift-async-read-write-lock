import Foundation

/// Async-friendly write-preferring read/write lock
@available(iOS 13.0, *)
class AsyncReadWriteLock: @unchecked Sendable {
    let mutex = NSLock()
    var activeReaders: Int = 0
    var activeWriter: Bool = false
    var pendingReaders: [UnsafeContinuation<Void, Never>] = []
    var pendingWriters: [UnsafeContinuation<Void, Never>] = []

    private func lock() {
        mutex.lock()
    }

    private func unlock() {
        mutex.unlock()
    }

    func lockForReading() async {
        lock()

        if !activeWriter && pendingWriters.isEmpty {
            activeReaders += 1
            unlock()
            return
        }

        await withUnsafeContinuation { continuation in
            pendingReaders.append(continuation)
            unlock()
        }
    }

    func unlockForReading() {
        lock()
        activeReaders -= 1
        assert(activeReaders >= 0)
        if activeReaders == 0 {
            resumePending()
        }
        unlock()
    }

    func lockForWriting() async {
        lock()

        if !activeWriter && activeReaders == 0 {
            activeWriter = true
            unlock()
            return
        }

        await withUnsafeContinuation { continuation in
            pendingWriters.append(continuation)
            unlock()
        }
    }

    func unlockForWriting() {
        lock()
        activeWriter = false
        resumePending()
        unlock()
    }

    private func resumePending() {
        assert(!activeWriter && activeReaders == 0)
        if !pendingWriters.isEmpty {
            let top = pendingWriters.removeFirst()
            activeWriter = true
            top.resume()
        } else {
            activeReaders = pendingReaders.count
            for r in pendingReaders {
                r.resume()
            }
            pendingReaders.removeAll(keepingCapacity: true)
        }
    }
}

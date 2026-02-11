import Foundation
import Atomics

/// Lock-free SPSC (Single Producer / Single Consumer) ring buffer for Float audio samples.
/// - RT thread friendly: no locks, no allocations during read/write.
/// - IMPORTANT: Not safe for multiple producers writing concurrently.
@available(macOS 13.0, iOS 16.0, *)
final class AtomicRingBuffer {

    private let capacity: Int
    private let mask: Int  // capacity must be power of two for mask fast-mod
    private let storage: UnsafeMutablePointer<Float>

    // Use monotonic counters (not wrapped by modulo) to make full/empty math simple.
    private let head = ManagedAtomic<Int>(0) // read cursor (monotonic)
    private let tail = ManagedAtomic<Int>(0) // write cursor (monotonic)

    /// Create buffer. For best performance, capacity should be power of two.
    /// If not power-of-two, this implementation will assert.
    init(capacity: Int) {
        precondition(capacity > 1, "capacity must be > 1")
        precondition((capacity & (capacity - 1)) == 0, "capacity must be power-of-two for this implementation")

        self.capacity = capacity
        self.mask = capacity - 1
        self.storage = .allocate(capacity: capacity)
        self.storage.initialize(repeating: 0, count: capacity)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    /// How many samples can be read right now.
    var availableToRead: Int {
        let t = tail.load(ordering: .acquiring)
        let h = head.load(ordering: .relaxed)
        return t - h
    }

    /// How many samples can be written right now.
    /// We keep one slot empty to distinguish full vs empty.
    var availableToWrite: Int {
        return (capacity - 1) - availableToRead
    }

    /// Producer: write up to `count` samples.
    /// Returns number of samples actually written (0..count).
    @discardableResult
    func write(_ data: UnsafePointer<Float>, count: Int) -> Int {
        if count <= 0 { return 0 }

        // Load cursors (SPSC: only producer updates tail, only consumer updates head)
        let h = head.load(ordering: .acquiring)
        let t = tail.load(ordering: .relaxed)

        let freeSpace = (capacity - 1) - (t - h)
        if freeSpace <= 0 { return 0 }

        let toWrite = min(count, freeSpace)
        let writePos = t & mask

        // Copy in up to two chunks (wrap-around)
        let firstPart = min(toWrite, capacity - writePos)
        memcpy(storage.advanced(by: writePos), data, firstPart * MemoryLayout<Float>.size)

        let secondPart = toWrite - firstPart
        if secondPart > 0 {
            memcpy(storage, data.advanced(by: firstPart), secondPart * MemoryLayout<Float>.size)
        }

        // Publish: after data is written, update tail with release semantics
        tail.store(t + toWrite, ordering: .releasing)
        return toWrite
    }

    /// Consumer: read up to `count` samples into `out`.
    /// If underrun, the remainder is zero-filled (silence).
    /// Returns number of samples actually read (0..count).
    @discardableResult
    func read(_ out: UnsafeMutablePointer<Float>, count: Int) -> Int {
        if count <= 0 { return 0 }

        let t = tail.load(ordering: .acquiring)
        let h = head.load(ordering: .relaxed)

        let available = t - h
        if available <= 0 {
            // no data -> silence
            memset(out, 0, count * MemoryLayout<Float>.size)
            return 0
        }

        let toRead = min(count, available)
        let readPos = h & mask

        let firstPart = min(toRead, capacity - readPos)
        memcpy(out, storage.advanced(by: readPos), firstPart * MemoryLayout<Float>.size)

        let secondPart = toRead - firstPart
        if secondPart > 0 {
            memcpy(out.advanced(by: firstPart), storage, secondPart * MemoryLayout<Float>.size)
        }

        // Advance head (publish with release)
        head.store(h + toRead, ordering: .releasing)

        // Fill rest with silence if underrun
        if toRead < count {
            memset(out.advanced(by: toRead), 0, (count - toRead) * MemoryLayout<Float>.size)
        }

        return toRead
    }

    /// Reset buffer cursors. (Call from non-RT thread if possible.)
    func reset() {
        head.store(0, ordering: .releasing)
        tail.store(0, ordering: .releasing)
    }
}

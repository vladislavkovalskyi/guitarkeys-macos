import Foundation
import Synchronization

/// Событие для аудиопотока. Планируется с точностью до сэмпла.
struct StringEvent {
    enum Kind: UInt8 {
        case pluck   = 0  // удар по струне
        case damp    = 1  // приглушить струну (отпустили аккорд)
        case silence = 2  // мгновенно оборвать
        case click   = 3  // щелчок метронома
    }

    var atSample: UInt64 = 0
    var string: Int32 = 0
    var frequency: Float = 0
    var velocity: Float = 0
    var brightness: Float = 0.5      // характер звукоизвлечения
    var pickPosition: Float = 0.13   // где задета струна: 0.05 у бриджа, 0.30 у грифа
    var sustain: Float = 3.0         // время затухания T60, сек
    var kind: Kind = .pluck
}

/// Односторонняя очередь без блокировок: пишет главный поток, читает аудиопоток.
final class EventQueue: @unchecked Sendable {
    private let capacity: Int
    private let mask: UInt64
    private let storage: UnsafeMutablePointer<StringEvent>
    private let writeIndex = Atomic<UInt64>(0)
    private let readIndex = Atomic<UInt64>(0)

    init(capacity: Int = 1024) {
        // Степень двойки — чтобы обходиться маской вместо деления.
        var size = 1
        while size < capacity { size <<= 1 }
        self.capacity = size
        self.mask = UInt64(size - 1)
        self.storage = UnsafeMutablePointer<StringEvent>.allocate(capacity: size)
        self.storage.initialize(repeating: StringEvent(), count: size)
    }

    deinit {
        storage.deinitialize(count: capacity)
        storage.deallocate()
    }

    /// Вызывается из главного потока.
    @discardableResult
    func push(_ event: StringEvent) -> Bool {
        let w = writeIndex.load(ordering: .relaxed)
        let r = readIndex.load(ordering: .acquiring)
        guard w &- r < UInt64(capacity) else { return false }  // переполнение — событие теряем
        storage[Int(w & mask)] = event
        writeIndex.store(w &+ 1, ordering: .releasing)
        return true
    }

    /// Вызывается только из аудиопотока.
    func pop() -> StringEvent? {
        let r = readIndex.load(ordering: .relaxed)
        let w = writeIndex.load(ordering: .acquiring)
        guard r != w else { return nil }
        let event = storage[Int(r & mask)]
        readIndex.store(r &+ 1, ordering: .releasing)
        return event
    }
}

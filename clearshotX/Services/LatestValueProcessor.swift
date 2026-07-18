//
//  LatestValueProcessor.swift
//  clearshotX
//

import Foundation

/// A one-element mailbox for expensive stream processing. When processing is busy,
/// a newer value replaces the pending value instead of building a stale queue.
nonisolated final class LatestValueProcessor<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private let queue: DispatchQueue
    private let process: @Sendable (Value) -> Void

    private var pendingValue: Value?
    private var isDraining = false
    private var isCancelled = false

    init(
        queue: DispatchQueue,
        process: @escaping @Sendable (Value) -> Void
    ) {
        self.queue = queue
        self.process = process
    }

    func submit(_ value: Value) {
        lock.lock()
        guard !isCancelled else {
            lock.unlock()
            return
        }

        pendingValue = value
        let shouldStartDraining = !isDraining
        if shouldStartDraining {
            isDraining = true
        }
        lock.unlock()

        if shouldStartDraining {
            queue.async { [weak self] in
                self?.drain()
            }
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        pendingValue = nil
        lock.unlock()
    }

    private func drain() {
        while true {
            lock.lock()
            guard !isCancelled, let value = pendingValue else {
                isDraining = false
                lock.unlock()
                return
            }
            pendingValue = nil
            lock.unlock()

            process(value)
        }
    }
}

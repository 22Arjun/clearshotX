//
//  ScrollingCaptureHUDViewModel.swift
//  clearshotX
//

import Combine

@MainActor
final class ScrollingCaptureHUDViewModel: ObservableObject {
    @Published private(set) var state: ScrollingCaptureHUDState = .starting

    private let finishHandler: () -> Void
    private let cancelHandler: () -> Void

    init(
        finish: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        finishHandler = finish
        cancelHandler = cancel
    }

    func update(_ state: ScrollingCaptureHUDState) {
        self.state = state
    }

    func finish() {
        guard state.canFinish else { return }
        finishHandler()
    }

    func cancel() {
        cancelHandler()
    }
}

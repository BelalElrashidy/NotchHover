import AppKit

/// A single countdown, surfaced in the resting bar while it runs.
final class CountdownTimer {
    private(set) var endDate: Date?
    var onTick: ((TimeInterval) -> Void)?
    var onFinish: (() -> Void)?

    private var timer: Timer?
    private let activityCenter: ActivityCenter

    init(activityCenter: ActivityCenter) {
        self.activityCenter = activityCenter
    }

    var isRunning: Bool { remaining > 0 }

    var remaining: TimeInterval {
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSinceNow)
    }

    func start(minutes: Int) {
        cancel()
        endDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        activityCenter.post(.timer(remaining: remaining))

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let left = self.remaining
            self.onTick?(left)
            if left <= 0 {
                self.finish()
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        endDate = nil
        onTick?(0)
    }

    private func finish() {
        cancel()
        NSSound(named: "Glass")?.play()
        onFinish?()
    }

    static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

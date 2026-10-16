import Foundation

/// Something worth showing in the resting bar for a moment.
enum LiveActivity: Equatable {
    case volume(level: Double, isMuted: Bool)
    case brightness(level: Double)
    case keyboardBacklight(level: Double)
    case battery(percent: Int, isCharging: Bool)
    case timer(remaining: TimeInterval)
    case notification(app: String, title: String)
    /// A call with a link, about to start. The peek has its Join button.
    case meeting(title: String)
    /// An accessory connected, or running low.
    case device(DeviceBattery)
    /// A Claude Code session finished its turn and is waiting on you.
    case claudeDone(project: String)

    /// How long the bar holds it before falling back to now playing.
    var duration: TimeInterval {
        switch self {
        case .volume, .brightness, .keyboardBacklight: return 1.4
        case .battery: return 2.5
        // Long enough to actually read.
        case .notification: return 4
        case .meeting: return 6
        case .device: return 3
        case .claudeDone: return 4
        case .timer: return 1.2
        }
    }
}

/// Fans system events out to whatever is showing the resting bar.
final class ActivityCenter {
    private var observers: [UUID: (LiveActivity) -> Void] = [:]

    @discardableResult
    func addObserver(_ handler: @escaping (LiveActivity) -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    func post(_ activity: LiveActivity) {
        DispatchQueue.main.async { [weak self] in
            self?.observers.values.forEach { $0(activity) }
        }
    }
}

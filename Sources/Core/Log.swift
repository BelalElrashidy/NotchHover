import os

enum Log {
    private static let subsystem = "com.notchhover.NotchHover"

    static let media = Logger(subsystem: subsystem, category: "media")
    static let shortcuts = Logger(subsystem: subsystem, category: "shortcuts")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let permissions = Logger(subsystem: subsystem, category: "permissions")
    static let system = Logger(subsystem: subsystem, category: "system")
}

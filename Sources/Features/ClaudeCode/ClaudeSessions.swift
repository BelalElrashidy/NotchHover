import Foundation

/// What a Claude Code session is doing, as far as its transcript says.
enum ClaudeSessionState: Equatable {
    /// Running a tool — the name is Claude Code's own, like "Bash" or "Edit".
    case working(tool: String)
    /// Waiting on the model.
    case thinking
    /// Finished its turn: your move.
    case waiting

    var label: String {
        switch self {
        case .working(let tool): return "Running \(tool)"
        case .thinking: return "Thinking"
        case .waiting: return "Waiting for you"
        }
    }
}

struct ClaudeSession: Equatable {
    let id: String
    let project: String
    let branch: String?
    let state: ClaudeSessionState
    let lastActivity: Date
}

struct ClaudeUsage: Equatable {
    var today = 0
    var todayOutput = 0
    var lastFiveHours = 0
}

/// Claude Code sessions and token use, read from the transcripts Claude Code keeps in
/// `~/.claude/projects`. Only metadata is taken — which project, which branch, what the
/// session is doing, how many tokens — never a prompt, a reply or a line of code. Nothing
/// leaves the Mac.
///
/// The transcripts are append-only JSON lines and can run to many megabytes, so each is
/// read once and then only from where the last read stopped.
final class ClaudeSessionMonitor {
    static let shared = ClaudeSessionMonitor()

    private(set) var sessions: [ClaudeSession] = []
    private(set) var usage = ClaudeUsage()
    /// A session that was working has finished its turn.
    var onFinished: ((ClaudeSession) -> Void)?

    private var observers: [UUID: () -> Void] = [:]
    private let queue = DispatchQueue(label: "com.notchhover.claudesessions", qos: .utility)
    private var timer: Timer?

    /// Per transcript: where reading stopped, and what has been learned so far.
    private struct Transcript {
        var offset: UInt64 = 0
        var project = ""
        var branch: String?
        var state: ClaudeSessionState = .waiting
        var lastActivity = Date.distantPast
        /// Usage by message id: Claude Code writes one line per content block, each
        /// carrying the same message's usage, so counting lines would count it twice.
        var usage: [String: (date: Date, total: Int, output: Int)] = [:]
    }

    private var transcripts: [URL: Transcript] = [:]

    /// A session untouched for this long is no longer shown as active.
    static let activeWindow: TimeInterval = 15 * 60

    static var projectsFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }

    @discardableResult
    func addObserver(_ handler: @escaping () -> Void) -> UUID {
        let id = UUID()
        observers[id] = handler
        return id
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func stop() {
        timer?.invalidate()
    }

    func refresh() {
        queue.async { [weak self] in
            guard let self else { return }
            let (sessions, usage) = self.scan()
            DispatchQueue.main.async { self.publish(sessions: sessions, usage: usage) }
        }
    }

    private func publish(sessions: [ClaudeSession], usage: ClaudeUsage) {
        let previous = Dictionary(self.sessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard sessions != self.sessions || usage != self.usage else { return }
        self.sessions = sessions
        self.usage = usage

        // Working to waiting is "Claude is done".
        for session in sessions where session.state == .waiting {
            guard let before = previous[session.id], before.state != .waiting else { continue }
            onFinished?(session)
        }
        observers.values.forEach { $0() }
    }

    // MARK: - Reading

    /// Preview hook: made-up sessions, so the card renders the same on every machine.
    func publishForPreview() {
        let now = Date()
        publish(sessions: [
            ClaudeSession(id: "a", project: "NotchHover", branch: "main", state: .working(tool: "Bash"), lastActivity: now),
            ClaudeSession(id: "b", project: "website", branch: "redesign", state: .waiting, lastActivity: now),
            ClaudeSession(id: "c", project: "api", branch: nil, state: .thinking, lastActivity: now)
        ], usage: ClaudeUsage(today: 4_200_000, todayOutput: 61_000, lastFiveHours: 2_900_000))
    }

    /// The self-test reads synchronously and reports what it found.
    func scanNow() -> ([ClaudeSession], ClaudeUsage) {
        queue.sync { scan() }
    }

    private func scan() -> ([ClaudeSession], ClaudeUsage) {
        let fileManager = FileManager.default
        let startOfDay = Calendar.current.startOfDay(for: Date())
        guard let projects = try? fileManager.contentsOfDirectory(at: Self.projectsFolder, includingPropertiesForKeys: nil) else {
            return ([], ClaudeUsage())
        }

        // Only transcripts touched today or in the last five hours matter — just after
        // midnight the five-hour window reaches back into yesterday.
        let since = min(startOfDay, Date().addingTimeInterval(-5 * 60 * 60))
        let files = projects
            .compactMap { try? fileManager.contentsOfDirectory(at: $0, includingPropertiesForKeys: [.contentModificationDateKey]) }
            .flatMap { $0 }
            .filter { $0.pathExtension == "jsonl" }
            .filter { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) >= since }

        for file in files {
            read(file)
        }

        let now = Date()
        let sessions = transcripts
            .filter { now.timeIntervalSince($0.value.lastActivity) < Self.activeWindow }
            .map { url, transcript in
                ClaudeSession(
                    id: url.deletingPathExtension().lastPathComponent,
                    project: transcript.project,
                    branch: transcript.branch,
                    state: transcript.state,
                    lastActivity: transcript.lastActivity
                )
            }
            .sorted { $0.lastActivity > $1.lastActivity }

        var usage = ClaudeUsage()
        let fiveHoursAgo = now.addingTimeInterval(-5 * 60 * 60)
        for transcript in transcripts.values {
            for entry in transcript.usage.values {
                if entry.date >= startOfDay {
                    usage.today += entry.total
                    usage.todayOutput += entry.output
                }
                if entry.date >= fiveHoursAgo { usage.lastFiveHours += entry.total }
            }
        }
        return (sessions, usage)
    }

    /// Reads whatever was appended since last time.
    private func read(_ url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        var transcript = transcripts[url] ?? Transcript()
        let size = (try? handle.seekToEnd()) ?? 0
        // Rewritten or replaced: start again.
        if size < transcript.offset { transcript = Transcript() }
        guard size > transcript.offset else { return }

        try? handle.seek(toOffset: transcript.offset)
        guard let data = try? handle.readToEnd() else { return }

        // Only whole lines: one being written right now is left for the next read.
        guard let lastNewline = data.lastIndex(of: UInt8(ascii: "\n")) else { return }
        let complete = data[data.startIndex...lastNewline]
        transcript.offset += UInt64(complete.count)

        for line in complete.split(separator: UInt8(ascii: "\n")) {
            Self.apply(line: Data(line), to: &transcript)
        }
        transcripts[url] = transcript
    }

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Takes the metadata from one transcript line. Content is looked at only to find the
    /// name of a tool being run.
    private static func apply(line: Data, to transcript: inout Transcript) {
        guard let entry = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let type = entry["type"] as? String,
              type == "user" || type == "assistant" else { return }

        let date = (entry["timestamp"] as? String).flatMap(timestampFormatter.date(from:)) ?? Date()
        if let cwd = entry["cwd"] as? String { transcript.project = URL(fileURLWithPath: cwd).lastPathComponent }
        // "HEAD" is what a detached checkout, or a folder that wasn't a repo yet, reports.
        if let branch = entry["gitBranch"] as? String, branch.isEmpty == false {
            transcript.branch = branch == "HEAD" ? nil : branch
        }

        let message = entry["message"] as? [String: Any] ?? [:]

        if type == "assistant", let id = message["id"] as? String, let usage = message["usage"] as? [String: Any] {
            func count(_ key: String) -> Int { usage[key] as? Int ?? 0 }
            let output = count("output_tokens")
            let total = count("input_tokens") + output + count("cache_creation_input_tokens") + count("cache_read_input_tokens")
            transcript.usage[id] = (date, total, output)
        }

        // Subagents run on side chains; the session's state is the main conversation's.
        guard (entry["isSidechain"] as? Bool) != true else { return }
        transcript.lastActivity = max(transcript.lastActivity, date)

        if type == "user" {
            transcript.state = .thinking
            return
        }
        let blocks = message["content"] as? [[String: Any]] ?? []
        if let tool = blocks.last(where: { $0["type"] as? String == "tool_use" })?["name"] as? String {
            transcript.state = .working(tool: tool)
        } else if message["stop_reason"] as? String == "end_turn" {
            transcript.state = .waiting
        }
    }
}

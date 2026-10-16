import Foundation
import Network

enum PermissionDecision: String {
    case allow
    case deny
    /// Hand the decision back to Claude Code's own prompt. Used for timeouts and
    /// anything the bridge cannot answer — never silently approve.
    case ask
}

/// A pending Claude Code tool-use request waiting on a human.
final class PermissionRequest {
    let id = UUID()
    let toolName: String
    let detail: String
    let cwd: String
    let receivedAt = Date()

    private let responder: (PermissionDecision) -> Void
    private var isAnswered = false

    init(toolName: String, detail: String, cwd: String, responder: @escaping (PermissionDecision) -> Void) {
        self.toolName = toolName
        self.detail = detail
        self.cwd = cwd
        self.responder = responder
    }

    var projectName: String {
        cwd.isEmpty ? "Claude Code" : URL(fileURLWithPath: cwd).lastPathComponent
    }

    func respond(_ decision: PermissionDecision) {
        guard isAnswered == false else { return }
        isAnswered = true
        responder(decision)
    }
}

/// Loopback JSON server that Claude Code's PreToolUse hook talks to. The hook blocks
/// while the panel shows the request, so the human decision still happens per request.
final class PermissionBridge {
    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NotchHover/bridge.json")
    }

    var onRequest: ((PermissionRequest) -> Void)?

    private var listener: NWListener?
    private let token = UUID().uuidString
    private let queue = DispatchQueue(label: "com.notchhover.permission-bridge")

    func start() {
        do {
            let parameters = NWParameters.tcp
            // Loopback only: nothing off this machine can reach the bridge.
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
            parameters.allowLocalEndpointReuse = true

            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    guard let port = listener.port?.rawValue else { return }
                    self?.writeConfig(port: port)
                    Log.permissions.notice("Bridge listening on 127.0.0.1:\(port, privacy: .public)")
                case .failed(let error):
                    Log.permissions.error("Bridge failed: \(error.localizedDescription, privacy: .public)")
                default:
                    break
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            Log.permissions.error("Bridge could not start: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        try? FileManager.default.removeItem(at: Self.configURL)
    }

    /// The hook reads the port and token from here; 0600 so only this user can answer prompts.
    private func writeConfig(port: UInt16) {
        let url = Self.configURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            let payload = ["port": Int(port), "token": token] as [String: Any]
            let data = try JSONSerialization.data(withJSONObject: payload)
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            Log.permissions.error("Could not write bridge config: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Connections

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            var buffer = buffer
            if let data {
                buffer.append(data)
            }

            if let newline = buffer.firstIndex(of: 0x0A) {
                self.process(line: Data(buffer[..<newline]), on: connection)
                return
            }

            guard isComplete == false, error == nil else {
                connection.cancel()
                return
            }
            self.receive(connection, buffer: buffer)
        }
    }

    private func process(line: Data, on connection: NWConnection) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let suppliedToken = object["token"] as? String,
              suppliedToken == token else {
            Log.permissions.error("Rejected a bridge request with a bad token")
            reply(.ask, on: connection)
            return
        }

        let toolName = object["tool"] as? String ?? "Unknown tool"
        let input = object["input"] as? [String: Any] ?? [:]
        let request = PermissionRequest(
            toolName: toolName,
            detail: Self.summarize(input),
            cwd: object["cwd"] as? String ?? ""
        ) { [weak self] decision in
            self?.reply(decision, on: connection)
        }

        Log.permissions.notice("Permission requested: \(toolName, privacy: .public)")
        DispatchQueue.main.async { [weak self] in
            self?.onRequest?(request)
        }
    }

    private func reply(_ decision: PermissionDecision, on connection: NWConnection) {
        let payload = ["decision": decision.rawValue]
        var data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        data.append(0x0A)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Pull the human-meaningful part out of a tool input blob.
    private static func summarize(_ input: [String: Any]) -> String {
        for key in ["command", "file_path", "path", "url", "pattern", "prompt"] {
            if let value = input[key] as? String, value.isEmpty == false {
                return value
            }
        }
        guard let data = try? JSONSerialization.data(withJSONObject: input),
              let text = String(data: data, encoding: .utf8) else {
            return "—"
        }
        return text
    }
}

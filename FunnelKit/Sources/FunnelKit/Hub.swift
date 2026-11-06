import Foundation
import Network

public struct HubControl: Codable, Sendable {
    public var version: Int
    public var port: Int
    public var token: String
    public var pid: Int32
}

public struct HubStatus: Codable, Sendable {
    public enum State: String, Codable, Sendable {
        case ready, setup, missingCLI, signedOut
    }
    public var api: Int
    public var version: String
    public var state: State
    public var demo: Bool
    public var budget: BudgetStatus
}

/// FunnelRadar's local API for Remote Code: 127.0.0.1 only, with a token from `control.json` (mode 0600).
/// Whoever runs the engine runs the hub. `POST /v1/yield` asks a `funnelradar-hub hub` to end when the app opens.
public final class Hub: @unchecked Sendable {
    public static let api = 1

    private let engine: Engine
    private let demo: Bool
    private let version: String
    private let onYield: @Sendable () -> Void
    private let token: String
    private let queue = DispatchQueue(label: "funnelradar.hub")
    private var listener: NWListener?

    public init(engine: Engine, demo: Bool, version: String, onYield: @escaping @Sendable () -> Void) {
        self.engine = engine
        self.demo = demo
        self.version = version
        self.onYield = onYield
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        token = bytes.map { String(format: "%02x", $0) }.joined()
    }

    /// The control file of a hub that is alive.
    public static func liveControl() -> HubControl? {
        guard let data = try? Data(contentsOf: Paths.control),
              let control = try? JSONDecoder().decode(HubControl.self, from: data), kill(control.pid, 0) == 0 else { return nil }
        return control
    }

    /// Asks a running `funnelradar-hub hub` to end, so the app can take over.
    public static func askLiveHubToYield() async {
        guard let control = liveControl(), control.pid != getpid() else { return }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(control.port)/v1/yield")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(control.token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
        for _ in 0..<30 where kill(control.pid, 0) == 0 {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    public func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .global())
            self?.receive(connection, buffer: Data())
        }
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state, let port = listener.port?.rawValue else { return }
            self.writeControl(port: Int(port))
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        if let control = Self.liveControl(), control.pid == getpid() {
            try? FileManager.default.removeItem(at: Paths.control)
        }
    }

    private func writeControl(port: Int) {
        let control = HubControl(version: Self.api, port: port, token: token, pid: getpid())
        guard let data = try? JSONEncoder().encode(control) else { return }
        Paths.prepare()
        FileManager.default.createFile(atPath: Paths.control.path, contents: data, attributes: [.posixPermissions: 0o600])
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, error in
            guard let self, error == nil else { connection.cancel(); return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                Task { await self.handle(request, on: connection) }
            } else if done || buffer.count > 1_000_000 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    struct Request {
        var method: String
        var path: String
        var authorization: String?
        var body: Data
    }

    static func parse(_ data: Data) -> Request? {
        guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let lines = String(decoding: data[..<end.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let first = lines[0].split(separator: " ")
        guard first.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = data[end.upperBound...]
        guard body.count >= length else { return nil }
        return Request(method: String(first[0]), path: String(first[1]), authorization: headers["authorization"], body: Data(body.prefix(length)))
    }

    private func respond(_ connection: NWConnection, status: Int = 200, json: Data) {
        let reason = status == 200 ? "OK" : "Error"
        var data = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(json.count)\r\nConnection: close\r\n\r\n".utf8)
        data.append(json)
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
    }

    private func status() async -> HubStatus {
        var state = HubStatus.State.ready
        if !Preferences.load().setupFinished, !demo {
            state = .setup
        } else if let error = await engine.lastError {
            if error == .cliMissing { state = .missingCLI }
            if error == .signedOut { state = .signedOut }
        }
        return HubStatus(api: Self.api, version: version, state: state, demo: demo, budget: await engine.budget())
    }

    private func handle(_ request: Request, on connection: NWConnection) async {
        // A constant-time comparison isn't needed: only local processes reach this port.
        guard request.authorization == "Bearer \(token)" else {
            respond(connection, status: 401, json: Data(#"{"error":"unauthorized"}"#.utf8))
            return
        }
        let path = request.path.split(separator: "?").first.map(String.init) ?? request.path
        switch (request.method, path) {
        case ("GET", "/v1/status"):
            respond(connection, json: encode(await status()))
        case ("GET", "/v1/portfolio"):
            respond(connection, json: encode(Self.summary(await engine.portfolio())))
        case ("GET", "/v1/alerts"):
            respond(connection, json: encode(await engine.recentAlerts()))
        case ("POST", "/v1/refresh"):
            let project = (try? JSONDecoder().decode([String: String].self, from: request.body))?["project"]
            respond(connection, json: Data(#"{"ok":true}"#.utf8))
            await engine.refresh(project: project)
        case ("POST", "/v1/yield"):
            respond(connection, json: Data(#"{"ok":true}"#.utf8))
            stop()
            onYield()
        case ("GET", "/v1/events"):
            await stream(to: connection)
        default:
            let prefix = "/v1/projects/"
            if request.method == "GET", path.hasPrefix(prefix), let report = await engine.report(String(path.dropFirst(prefix.count))) {
                respond(connection, json: encode(report))
            } else {
                respond(connection, status: 404, json: Data(#"{"error":"not found"}"#.utf8))
            }
        }
    }

    /// The list without each project's heavy series, for a phone on a slow connection.
    static func summary(_ portfolio: Portfolio) -> Portfolio {
        var copy = portfolio
        copy.indexed = []
        copy.reports = copy.reports.map { report in
            var light = report
            light.dailyUsers = Array(report.dailyUsers.suffix(30))
            light.monthlyUsers = []
            light.eventNames = []
            light.anomalies = []
            light.insights.trend = []
            light.insights.stickinessByMonth = []
            light.retention?.rows = []
            light.retention?.curve = []
            return light
        }
        return copy
    }

    /// Server-sent events until the client leaves.
    private func stream(to connection: NWConnection) async {
        let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n: hello\n\n"
        connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
        let events = await engine.events()
        let consumer = Task {
            for await event in events {
                let text: String
                switch event {
                case .portfolio: text = "event: portfolio\ndata: {}\n\n"
                case .alert(let alert): text = "event: alert\ndata: \(String(decoding: encode(alert), as: UTF8.self))\n\n"
                }
                connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in })
            }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled: consumer.cancel()
            default: break
            }
        }
        connection.receiveMessage { _, _, _, _ in
            connection.cancel()
        }
        await consumer.value
    }
}

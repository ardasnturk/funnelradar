import Foundation

/// Puts `mp` on a Mac that has none, at a pinned version, in FunnelRadar's own folder.
/// macOS ships Python 3.9 and the CLI needs 3.10, so the order is: `uv`, which can fetch a Python
/// by itself; a new enough `python3`; Homebrew, to get `uv`; otherwise a clear message.
public enum ToolInstaller {
    public static let package = "mixpanel-headless"
    /// A pre-release, so never "latest": a new version may change the JSON this app reads.
    public static let version = "0.4.0"
    public static var pin: String { "\(package)==\(version)" }
    /// The venv holds pandas and more. FunnelRadar says so, and wants this much free.
    static let spaceNeeded: Int64 = 500_000_000

    public enum Stage: Sendable, Equatable {
        case gettingUV, fetchingPython, makingEnvironment, installing, checking
    }

    public enum Plan: Sendable, Equatable {
        case uv(String)
        case python(String)
        case homebrew(String)
        case manual
    }

    public static var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: Paths.mp.path)
    }

    static func plan(uv: String?, python: String?, brew: String?) -> Plan {
        if let uv { return .uv(uv) }
        if let python { return .python(python) }
        if let brew { return .homebrew(brew) }
        return .manual
    }

    /// `Python 3.13.5` → true. 3.10 is the oldest the CLI runs on.
    static func isUsable(pythonVersion text: String) -> Bool {
        let parts = text.split(whereSeparator: \.isWhitespace).last?.split(separator: ".").compactMap { Int($0) } ?? []
        guard parts.count >= 2 else { return false }
        return parts[0] > 3 || (parts[0] == 3 && parts[1] >= 10)
    }

    /// `/usr/bin/python3` is left out: it's 3.9, and on a Mac without developer tools running it
    /// opens Apple's install dialog.
    static func findPython() async -> String? {
        let env = await ShellEnvironment.shared.environment()
        for name in ["python3.14", "python3.13", "python3.12", "python3.11", "python3.10", "python3"] {
            guard let path = await ShellEnvironment.shared.which(name), !path.hasPrefix("/usr/bin/"),
                  let result = try? await ProcessRunner.run(path, ["--version"], environment: env, timeout: 10),
                  result.code == 0, isUsable(pythonVersion: result.text + result.stderr) else { continue }
            return path
        }
        return nil
    }

    private static func check(_ result: ProcessResult) throws {
        guard result.code == 0 else {
            let line = result.stderr.split(separator: "\n").last.map(String.init)
            throw FunnelError.failed(line ?? "The install failed (\(result.code)).")
        }
    }

    public static func install(progress: @escaping @Sendable (Stage) -> Void) async throws {
        Paths.prepare()
        if let free = try? Paths.home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
           free < spaceNeeded {
            throw FunnelError.failed("Not enough free disk space. The install needs about 500 MB.")
        }
        let shell = ShellEnvironment.shared
        var env = await shell.environment()
        // Whatever Python uv fetches stays with FunnelRadar, and goes when its folder does.
        env["UV_PYTHON_INSTALL_DIR"] = Paths.python.path
        env.removeValue(forKey: "VIRTUAL_ENV")
        env.removeValue(forKey: "PYTHONPATH")

        var plan = plan(uv: await shell.which("uv"), python: await findPython(), brew: await shell.which("brew"))
        if case .homebrew(let brew) = plan {
            progress(.gettingUV)
            try check(try await ProcessRunner.run(brew, ["install", "uv"], environment: env, timeout: 600))
            await shell.invalidate()
            guard let uv = await shell.which("uv") else { throw FunnelError.failed("Homebrew installed uv, but it can't be found.") }
            plan = .uv(uv)
        }

        try? FileManager.default.removeItem(at: Paths.venv)
        do {
            switch plan {
            case .uv(let uv):
                progress(.fetchingPython)
                try check(try await ProcessRunner.run(uv, ["venv", "--python", "3.12", "--no-project", Paths.venv.path], environment: env, timeout: 600))
                progress(.installing)
                let python = Paths.venv.appendingPathComponent("bin/python").path
                try check(try await ProcessRunner.run(uv, ["pip", "install", "--python", python, pin], environment: env, timeout: 900))
            case .python(let python):
                progress(.makingEnvironment)
                try check(try await ProcessRunner.run(python, ["-m", "venv", Paths.venv.path], environment: env, timeout: 300))
                progress(.installing)
                let pip = Paths.venv.appendingPathComponent("bin/pip").path
                try check(try await ProcessRunner.run(pip, ["install", "--disable-pip-version-check", pin], environment: env, timeout: 900))
            case .homebrew, .manual:
                throw FunnelError.failed("FunnelRadar needs Python 3.10 or newer. Install uv (brew install uv, or astral.sh/uv) and try again.")
            }
            progress(.checking)
            guard await MPCLI().version() == version else { throw FunnelError.failed("mp was installed but can't be started.") }
        } catch {
            try? FileManager.default.removeItem(at: Paths.venv)
            throw error
        }
    }
}

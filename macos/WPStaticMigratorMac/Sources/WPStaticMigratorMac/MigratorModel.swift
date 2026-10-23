import AppKit
import CryptoKit
import Foundation

@MainActor
final class MigratorModel: ObservableObject {
    enum Operation: String, CaseIterable, Identifiable {
        case initialize = "初期設定"
        case crawl = "サイト取得"
        case build = "HTML生成"
        case validate = "検証"
        case all = "すべて実行"

        var id: Self { self }
        var command: String {
            switch self {
            case .initialize: "init"
            case .crawl: "crawl"
            case .build: "build"
            case .validate: "validate"
            case .all: "all"
            }
        }
    }

    @Published var sourceURL = ""
    @Published var projectPath = ""
    @Published var configuredOrigin: String?
    @Published var port = "8080"
    @Published var log = "Mac用 WP Static Migrator を起動しました。\n"
    @Published var isRunning = false
    @Published var previewIsRunning = false
    @Published var status = "準備完了"
    @Published var alertMessage: String?
    @Published var showsNodeInstallPrompt = false
    @Published var isInstallingNode = false

    private var task: Process?
    private var previewTask: Process?

    var projectURL: URL? {
        guard !projectPath.isEmpty else { return nil }
        return URL(fileURLWithPath: projectPath, isDirectory: true)
    }

    var hasProject: Bool { projectURL != nil }
    var canInitialize: Bool {
        hasProject && normalizedOrigin(sourceURL) != nil && (configuredOrigin == nil || configurationMismatch)
    }
    var configurationMismatch: Bool {
        guard let configuredOrigin, let enteredOrigin = normalizedOrigin(sourceURL) else { return false }
        return enteredOrigin != configuredOrigin
    }

    func chooseProjectFolder() {
        let panel = NSOpenPanel()
        panel.title = "作業フォルダを選択"
        panel.prompt = "選択"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            projectPath = url.path
            loadConfiguration(from: url)
        }
    }

    func run(_ operation: Operation) {
        guard let projectURL else {
            alertMessage = "作業フォルダを選択してください。"
            return
        }
        if operation == .initialize, configuredOrigin != nil {
            guard configurationMismatch else {
                alertMessage = "このフォルダはすでに \(configuredOrigin ?? sourceURL) 用に設定されています。"
                return
            }
            do {
                try updateConfiguration(at: projectURL)
                return
            } catch {
                handle(error)
                return
            }
        }
        guard operation != .initialize || canInitialize else {
            alertMessage = "http:// または https:// で始まるWordPress URLを入力してください。"
            return
        }
        if operation != .initialize && configuredOrigin == nil {
            alertMessage = "このフォルダには初期設定がありません。WordPress URLを入力して「初期設定を作成」を実行してください。"
            return
        }
        if operation != .initialize && configurationMismatch {
            do {
                try updateConfiguration(at: projectURL)
            } catch {
                handle(error)
                return
            }
        }
        guard !isRunning else { return }

        do {
            let node = try RuntimeLocator.nodeExecutable(projectURL: projectURL)
            let cli = try RuntimeLocator.cliScript()
            var arguments = [cli.path, operation.command]
            if operation == .initialize { arguments += ["--url", sourceURL] }
            arguments += ["--output", projectURL.path]

            let process = Process()
            process.executableURL = node
            process.arguments = arguments
            process.currentDirectoryURL = RuntimeLocator.runtimeRoot(for: cli)
            process.environment = RuntimeLocator.environment()
            attachOutput(of: process, prefix: "")
            process.terminationHandler = { [weak self] process in
                Task { @MainActor in
                    guard let self else { return }
                    self.isRunning = false
                    self.task = nil
                    if process.terminationStatus == 0 {
                        self.status = "\(operation.rawValue)が完了しました"
                        self.appendLog("\n✓ \(operation.rawValue) 完了\n")
                        if operation == .initialize, let projectURL = self.projectURL {
                            self.loadConfiguration(from: projectURL)
                        }
                    } else {
                        self.status = "\(operation.rawValue)で問題が見つかりました"
                        self.appendLog("\n⚠︎ 終了コード: \(process.terminationStatus)\n")
                    }
                }
            }

            appendLog("\n▶︎ \(operation.rawValue)\n")
            status = "\(operation.rawValue)を実行中…"
            isRunning = true
            task = process
            try process.run()
        } catch {
            isRunning = false
            task = nil
            handle(error)
        }
    }

    func cancelCurrentOperation() {
        guard let task, task.isRunning else { return }
        task.interrupt()
        appendLog("\n停止を要求しました。\n")
    }

    func togglePreview() {
        previewIsRunning ? stopPreview() : startPreview()
    }

    func startPreview() {
        guard let projectURL else {
            alertMessage = "作業フォルダを選択してください。"
            return
        }
        guard let portNumber = Int(port), (1...65535).contains(portNumber) else {
            alertMessage = "ポート番号は1〜65535で入力してください。"
            return
        }
        do {
            let node = try RuntimeLocator.nodeExecutable(projectURL: projectURL)
            let cli = try RuntimeLocator.cliScript()
            let previewScript = RuntimeLocator.runtimeRoot(for: cli).appendingPathComponent("scripts/preview.js")
            let process = Process()
            process.executableURL = node
            process.arguments = [previewScript.path]
            process.currentDirectoryURL = RuntimeLocator.runtimeRoot(for: cli)
            var environment = RuntimeLocator.environment()
            environment["WPSM_WORKDIR"] = projectURL.path
            environment["WPSM_PORT"] = String(portNumber)
            process.environment = environment
            attachOutput(of: process, prefix: "[Preview] ")
            process.terminationHandler = { [weak self] process in
                Task { @MainActor in
                    self?.previewIsRunning = false
                    self?.previewTask = nil
                    self?.status = process.terminationStatus == 0 ? "プレビューを終了しました" : "プレビューを終了しました（コード \(process.terminationStatus)）"
                }
            }
            try process.run()
            previewTask = process
            previewIsRunning = true
            status = "プレビューを起動しました"
            appendLog("\n▶︎ Preview: http://127.0.0.1:\(portNumber)/\n")
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                openPreview()
            }
        } catch {
            previewIsRunning = false
            previewTask = nil
            handle(error)
        }
    }

    func stopPreview() {
        guard let previewTask, previewTask.isRunning else { return }
        previewTask.terminate()
        status = "プレビューを停止しています…"
    }

    func openPreview() {
        guard let portNumber = Int(port), let url = URL(string: "http://127.0.0.1:\(portNumber)/") else { return }
        NSWorkspace.shared.open(url)
    }

    func revealProject() {
        guard let projectURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([projectURL])
    }

    func installNodeInProject() {
        guard let projectURL else {
            alertMessage = "先に作業フォルダを選択してください。"
            return
        }
        guard !isInstallingNode else { return }
        isInstallingNode = true
        status = "Node.jsを作業フォルダへインストール中…"
        appendLog("\n▶︎ Node.js 20を .wpsm/runtime/node へインストールします\n")
        Task {
            do {
                let executable = try await LocalNodeInstaller.install(in: projectURL)
                isInstallingNode = false
                status = "Node.jsのローカルインストールが完了しました"
                appendLog("✓ インストール完了: \(executable.path)\n")
            } catch {
                isInstallingNode = false
                status = "Node.jsのインストールに失敗しました"
                alertMessage = error.localizedDescription
                appendLog("⚠︎ \(error.localizedDescription)\n")
            }
        }
    }

    func clearLog() { log = "" }

    private func loadConfiguration(from projectURL: URL) {
        let configURL = projectURL.appendingPathComponent("config.json")
        guard
            let data = try? Data(contentsOf: configURL),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let origin = object["origin"] as? String,
            let normalized = normalizedOrigin(origin)
        else {
            configuredOrigin = nil
            status = "新しいプロジェクトの保存先です"
            return
        }
        configuredOrigin = normalized
        sourceURL = normalized
        status = "\(normalized) のプロジェクトを選択しました"
    }

    private func updateConfiguration(at projectURL: URL) throws {
        let configURL = projectURL.appendingPathComponent("config.json")
        let data = try Data(contentsOf: configURL)
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let components = URLComponents(string: sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let origin = normalizedOrigin(sourceURL),
              let host = components.host else {
            throw ConfigurationError.invalidURL
        }
        object["origin"] = origin
        object["includeHosts"] = [host]
        object["startPaths"] = [components.path.isEmpty ? "/" : components.path]
        let updated = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        var terminated = updated
        terminated.append(0x0A)
        try terminated.write(to: configURL, options: .atomic)
        configuredOrigin = origin
        sourceURL = origin
        status = "設定URLを \(origin) に更新しました"
        appendLog("\n✓ 設定URLを更新: \(origin)\n")
    }

    private func normalizedOrigin(_ value: String) -> String? {
        guard var components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              components.host != nil else { return nil }
        components.scheme = scheme
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func attachOutput(of process: Process, prefix: String) {
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.appendLog(prefix + text) }
        }
    }

    private func appendLog(_ text: String) {
        log += text
    }

    private func handle(_ error: Error) {
        if case RuntimeLocator.RuntimeError.nodeNotFound = error {
            showsNodeInstallPrompt = true
        } else {
            alertMessage = error.localizedDescription
        }
    }

    deinit {
        task?.terminate()
        previewTask?.terminate()
    }
}

enum ConfigurationError: LocalizedError {
    case invalidURL

    var errorDescription: String? {
        "http:// または https:// で始まる正しいURLを入力してください。"
    }
}

enum RuntimeLocator {
    enum RuntimeError: LocalizedError {
        case nodeNotFound
        case cliNotFound

        var errorDescription: String? {
            switch self {
            case .nodeNotFound:
                "Node.jsが見つかりません。Node.js 20以上をインストールして、アプリを再起動してください。"
            case .cliNotFound:
                "WP Static MigratorのCLIが見つかりません。アプリを再ビルドしてください。"
            }
        }
    }

    static func nodeExecutable(projectURL: URL?) throws -> URL {
        var candidates: [String] = []
        if let projectURL {
            candidates.append(projectURL.appendingPathComponent(".wpsm/runtime/node/bin/node").path)
        }
        candidates += [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { "\($0)/node" }
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }
        throw RuntimeError.nodeNotFound
    }

    static func cliScript() throws -> URL {
        var candidates: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent("Runtime/bin/wp-static-migrator.js"))
        }
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("bin/wp-static-migrator.js"))
        let packageDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        candidates.append(packageDirectory.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("bin/wp-static-migrator.js"))
        if let url = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) {
            return url
        }
        throw RuntimeError.cliNotFound
    }

    static func runtimeRoot(for cli: URL) -> URL {
        cli.deletingLastPathComponent().deletingLastPathComponent()
    }

    static func environment() -> [String: String] {
        var value = ProcessInfo.processInfo.environment
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", value["PATH"] ?? ""].filter { !$0.isEmpty }
        value["PATH"] = paths.joined(separator: ":")
        return value
    }
}

enum LocalNodeInstaller {
    enum InstallError: LocalizedError {
        case unsupportedArchitecture
        case releaseNotFound
        case checksumMismatch
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedArchitecture:
                "このMacのCPUアーキテクチャには対応していません。"
            case .releaseNotFound:
                "Node.js 20のmacOS向け配布ファイルが見つかりません。"
            case .checksumMismatch:
                "ダウンロードしたNode.jsの検証に失敗しました。ファイルは使用していません。"
            case .extractionFailed(let detail):
                "Node.jsを展開できませんでした。\(detail)"
            }
        }
    }

    static func install(in projectURL: URL) async throws -> URL {
        let architecture: String
        #if arch(arm64)
        architecture = "arm64"
        #elseif arch(x86_64)
        architecture = "x64"
        #else
        throw InstallError.unsupportedArchitecture
        #endif

        let baseURL = URL(string: "https://nodejs.org/dist/latest-v20.x/")!
        let (checksumData, checksumResponse) = try await URLSession.shared.data(from: baseURL.appendingPathComponent("SHASUMS256.txt"))
        try validateHTTP(checksumResponse)
        guard let checksumList = String(data: checksumData, encoding: .utf8) else {
            throw InstallError.releaseNotFound
        }
        let suffix = "-darwin-\(architecture).tar.xz"
        guard let line = checksumList.split(separator: "\n").first(where: { $0.hasSuffix(suffix) }) else {
            throw InstallError.releaseNotFound
        }
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count >= 2 else { throw InstallError.releaseNotFound }
        let expectedHash = String(fields[0]).lowercased()
        let filename = String(fields[1])

        let runtime = projectURL.appendingPathComponent(".wpsm/runtime", isDirectory: true)
        let archive = runtime.appendingPathComponent(filename)
        let staging = runtime.appendingPathComponent("node-new", isDirectory: true)
        let destination = runtime.appendingPathComponent("node", isDirectory: true)
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
        let privateRoot = projectURL.appendingPathComponent(".wpsm", isDirectory: true)
        let ignoreFile = privateRoot.appendingPathComponent(".gitignore")
        if !FileManager.default.fileExists(atPath: ignoreFile.path) {
            try Data("*\n".utf8).write(to: ignoreFile, options: .atomic)
        }

        let (temporaryDownload, response) = try await URLSession.shared.download(from: baseURL.appendingPathComponent(filename))
        try validateHTTP(response)
        if FileManager.default.fileExists(atPath: archive.path) {
            try FileManager.default.removeItem(at: archive)
        }
        try FileManager.default.moveItem(at: temporaryDownload, to: archive)

        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        let actualHash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actualHash == expectedHash else {
            try? FileManager.default.removeItem(at: archive)
            throw InstallError.checksumMismatch
        }

        if FileManager.default.fileExists(atPath: staging.path) {
            try FileManager.default.removeItem(at: staging)
        }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xJf", archive.path, "--strip-components=1", "-C", staging.path]
        let errorPipe = Pipe()
        tar.standardError = errorPipe
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else {
            let detail = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            try? FileManager.default.removeItem(at: staging)
            try? FileManager.default.removeItem(at: archive)
            throw InstallError.extractionFailed(detail)
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: staging, to: destination)
        try? FileManager.default.removeItem(at: archive)
        let executable = destination.appendingPathComponent("bin/node")
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw InstallError.extractionFailed("実行ファイルが見つかりません。")
        }
        return executable
    }

    private static func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

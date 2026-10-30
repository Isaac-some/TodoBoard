import Foundation

struct CodexChatFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum CodexInstallation {
    static func locateExecutable() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            home.appendingPathComponent(".local/bin/codex").path
        ] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map { URL(fileURLWithPath: $0) }
    }

}

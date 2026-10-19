import Foundation
import DevKitCore

final class SpyOutput: TextOutput {
    private(set) var standardOutput = ""
    private(set) var standardError = ""

    func writeOut(_ text: String) { standardOutput += text }
    func writeError(_ text: String) { standardError += text }
}

final class SpyLauncher: ProcessLauncher {
    private(set) var plans: [RunPlan] = []
    var result = LaunchResult(outcome: .exited(0), forwardedSignal: nil)
    var error: (any Error)?

    func run(_ plan: RunPlan) throws -> LaunchResult {
        plans.append(plan)
        if let error { throw error }
        return result
    }
}

final class StubRepositoryLocator: RepositoryLocator {
    private(set) var askedDirectories: [URL] = []
    var result: Result<URL, any Error> = .success(URL(fileURLWithPath: "/repo", isDirectory: true))

    func topLevel(of directory: URL) throws -> URL {
        askedDirectories.append(directory)
        return try result.get()
    }
}

struct StubDirectoryInspector: DirectoryInspector {
    var exists = true

    func isDirectory(at url: URL) -> Bool { exists }
}

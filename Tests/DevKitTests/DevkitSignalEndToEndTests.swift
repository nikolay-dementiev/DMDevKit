import XCTest
import Foundation

final class DevkitSignalEndToEndTests: XCTestCase {
    func test_sigterm_isForwardedAndDevkitExitsWith143() throws {
        let sut = try makeSUT()

        let status = try sut.runUntilWaiting { $0.terminate() }

        XCTAssertEqual(status, 143, "128 + SIGTERM (15), and the long wait of the child did not hold devkit up")
    }

    func test_sigint_isForwardedAndDevkitExitsWith130() throws {
        let sut = try makeSUT()

        let status = try sut.runUntilWaiting { $0.interrupt() }

        XCTAssertEqual(status, 130, "128 + SIGINT (2)")
    }

    // MARK: - Helpers

    final class SUT {
        let fixture: EndToEndFixture
        let repository: URL
        let devkit: URL
        let pidFile: URL

        init(fixture: EndToEndFixture, repository: URL, devkit: URL) {
            self.fixture = fixture
            self.repository = repository
            self.devkit = devkit
            self.pidFile = fixture.directory.appendingPathComponent("xcrun.pid")
        }

        /// Starts devkit on a script that is stuck in a 30 second `sleep`, calls `deliver`, and returns devkit's exit status.
        func runUntilWaiting(deliver: (Process) -> Void) throws -> Int32 {
            let process = Process()
            process.executableURL = devkit
            process.arguments = ["prepare-simulator", "iPhone 15", "17.5"]
            process.currentDirectoryURL = repository
            process.environment = fixture.shimmedEnvironment()
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            defer {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                if let text = try? String(contentsOf: pidFile, encoding: .utf8), let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    kill(pid, SIGKILL)
                }
            }
            XCTAssertTrue(wait(timeout: 10) { FileManager.default.fileExists(atPath: pidFile.path) }, "the script reached the shim")
            deliver(process)
            XCTAssertTrue(wait(timeout: 10) { !process.isRunning }, "devkit ended after the signal")
            return process.terminationStatus
        }

        private func wait(timeout: TimeInterval, until condition: () -> Bool) -> Bool {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if condition() { return true }
                usleep(50_000)
            }
            return condition()
        }
    }

    private func makeSUT() throws -> SUT {
        let fixture = try EndToEndFixture()
        let directory = fixture.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let sut = SUT(fixture: fixture, repository: try fixture.makeRepository(), devkit: EndToEndFixture.devkitURL(for: Self.self))
        // Stands in for `xcrun simctl list -j`, the first call of the script, and never answers.
        try fixture.writeShim(named: "xcrun", body: "echo $$ > '\(sut.pidFile.path)'\nexec sleep 30\n")
        return sut
    }
}

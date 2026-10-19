import XCTest
import Foundation

final class PrepareSimulatorEndToEndTests: XCTestCase {
    private let udid = "A1B2C3D4-0000-1111-2222-333344445555"

    func test_script_isTheLibraryCopyByteForByte() throws {
        let script = EndToEndFixture.resourceFolder(for: Self.self).appendingPathComponent("Scripts/prepare-simulator.sh")

        XCTAssertEqual(
            try EndToEndFixture.gitBlobHash(of: script),
            "41c44a0032dc7adc6c674c4089549f9b2a2cfbd6",
            "the blob that DMAction, DMVariableBlurView and DMUnLoader have at origin/main"
        )
    }

    func test_throughDevkit_printsTheSameAsTheScriptRunDirectly() throws {
        let sut = try makeSUT()
        let arguments = ["iPhone 15", "17.5"]

        let direct = try sut.fixture.capture("/bin/bash", [sut.script.path] + arguments, in: sut.repository, environment: sut.environment)
        let throughDevkit = try sut.fixture.capture(sut.devkit.path, ["prepare-simulator"] + arguments, in: sut.repository, environment: sut.environment)

        XCTAssertEqual(direct.status, 0, "the shimmed simulator list has the device")
        XCTAssertEqual(direct.standardOutput, udid + "\n", "standard output is the udid line and nothing else")
        XCTAssertEqual(throughDevkit, direct, "status, standard output and standard error are the same through devkit")
    }

    func test_throughDevkit_missingArgumentsGiveTheScriptsUsageError() throws {
        let sut = try makeSUT()

        let direct = try sut.fixture.capture("/bin/bash", [sut.script.path], in: sut.repository, environment: sut.environment)
        let throughDevkit = try sut.fixture.capture(sut.devkit.path, ["prepare-simulator"], in: sut.repository, environment: sut.environment)

        XCTAssertEqual(direct.status, 2, "the script's own usage status")
        XCTAssertEqual(throughDevkit, direct, "devkit adds nothing to the usage error")
    }

    func test_throughDevkit_unknownDeviceTypeIsExitOneWithEmptyStandardOutput() throws {
        let sut = try makeSUT()

        let throughDevkit = try sut.fixture.capture(sut.devkit.path, ["prepare-simulator", "iPhone 99", "17.5"], in: sut.repository, environment: sut.environment)

        XCTAssertEqual(throughDevkit.status, 1, "no device type of that name")
        XCTAssertEqual(throughDevkit.standardOutput, "", "no udid line on failure")
    }

    // MARK: - Helpers

    struct SUT {
        let fixture: EndToEndFixture
        let repository: URL
        let devkit: URL
        let script: URL
        let environment: [String: String]
    }

    private func makeSUT() throws -> SUT {
        let fixture = try EndToEndFixture()
        let directory = fixture.directory
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        // Imitates `xcrun simctl` as Xcode prints it: `simctl list -j` has the keys devicetypes, runtimes and devices,
        // and `simctl bootstatus <udid> -b` prints progress and exits 0 once the device is booted.
        try fixture.writeShim(named: "xcrun", body: """
        if [ "$1 $2" = "simctl list" ] && [ "$3" = "-j" ]; then
        cat <<'JSON'
        {"devicetypes":[{"name":"iPhone 15","identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-15"}],
         "runtimes":[{"isAvailable":true,"version":"17.5","identifier":"com.apple.CoreSimulator.SimRuntime.iOS-17-5",
           "supportedDeviceTypes":[{"identifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-15"}]}],
         "devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-5":[{"name":"iPhone 15","udid":"\(udid)","isAvailable":true}]}}
        JSON
        exit 0
        fi
        if [ "$1 $2" = "simctl bootstatus" ]; then echo "Device already booted." ; exit 0; fi
        echo "unexpected xcrun call: $*" >&2; exit 64
        """)
        return SUT(
            fixture: fixture,
            repository: try fixture.makeRepository(),
            devkit: EndToEndFixture.devkitURL(for: Self.self),
            script: EndToEndFixture.resourceFolder(for: Self.self).appendingPathComponent("Scripts/prepare-simulator.sh"),
            environment: fixture.shimmedEnvironment()
        )
    }
}

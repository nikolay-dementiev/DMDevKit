import XCTest
import Foundation
import DevKitCore

/// The build system decides where the scripts land next to the executable: the native one of SwiftPM copies the folder into the bundle,
/// the Swift Build system of Swift 6.4 wraps the bundle in the macOS layout.
final class ResourceFolderLocatorTests: XCTestCase {
    private static let nativeFolder = "/opt/build/debug/DMDevKit_devkit.bundle/Resources"
    private static let swiftBuildFolder = "/opt/build/debug/DMDevKit_devkit.bundle/Contents/Resources/Resources"

    func test_folder_ofTheNativeLayout_isTheResourcesFolderOfTheBundle() {
        let sut = makeSUT(existing: [Self.nativeFolder])

        let folder = sut.folder(besideExecutable: URL(fileURLWithPath: "/opt/build/debug/devkit"))

        XCTAssertEqual(folder.path, Self.nativeFolder, "the flat layout of the native build system is found")
    }

    func test_folder_ofTheSwiftBuildLayout_isTheResourcesFolderInsideContents() {
        let sut = makeSUT(existing: [Self.swiftBuildFolder])

        let folder = sut.folder(besideExecutable: URL(fileURLWithPath: "/opt/build/debug/devkit"))

        XCTAssertEqual(folder.path, Self.swiftBuildFolder, "the macOS layout of the Swift Build system is found")
    }

    func test_folder_whenBothLayoutsExist_isTheNativeOne() {
        let sut = makeSUT(existing: [Self.swiftBuildFolder, Self.nativeFolder])

        let folder = sut.folder(besideExecutable: URL(fileURLWithPath: "/opt/build/debug/devkit"))

        XCTAssertEqual(folder.path, Self.nativeFolder, "the order of the candidates is fixed, the native layout first")
    }

    func test_folder_whenNoLayoutExists_namesTheNativeFolderForTheMessage() {
        let sut = makeSUT(existing: [])

        let folder = sut.folder(besideExecutable: URL(fileURLWithPath: "/opt/build/debug/devkit"))

        XCTAssertEqual(folder.path, Self.nativeFolder, "the missing-folder message names the folder that a plain build makes")
    }

    // MARK: - Helpers

    private struct ExistingDirectories: DirectoryInspector {
        let paths: Set<String>

        func isDirectory(at url: URL) -> Bool { paths.contains(url.path) }
    }

    private func makeSUT(existing: Set<String>) -> ResourceFolderLocator {
        ResourceFolderLocator(directoryInspector: ExistingDirectories(paths: existing))
    }
}

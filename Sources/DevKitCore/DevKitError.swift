/// A failure of `devkit` itself, as opposed to a failure of the script it runs.
public enum DevKitError: Error, Equatable {
    /// The working directory is not inside a git repository.
    case notInRepository(directory: String)
    /// The resource folder that holds the scripts is not there.
    case missingResourceFolder(path: String)
    /// The child could not be started.
    case cannotStart(executable: String, reason: String)

    // One line for the user, without the `devkit:` prefix.
    var message: String {
        switch self {
        case .notInRepository(let directory):
            "\(directory) is not inside a git repository"
        case .missingResourceFolder(let path):
            "the resource folder \(path) is missing"
        case .cannotStart(let executable, let reason):
            "cannot start \(executable): \(reason)"
        }
    }
}

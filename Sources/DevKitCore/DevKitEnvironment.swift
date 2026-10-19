/// The variables `devkit` gives every script: explicit paths, so that no script derives the repository from its own location.
enum DevKitEnvironment {
    /// The git top level of the working directory `devkit` was started in.
    static let repositoryRoot = "DEVKIT_REPO_ROOT"
    /// The folder that holds the scripts.
    static let resources = "DEVKIT_RESOURCES"
    /// The configuration file of the repository: `<root>/devkit.conf`.
    static let configuration = "DEVKIT_CONF"
    /// The folder scripts may write to: `<root>/.build/devkit`. It is not created.
    static let work = "DEVKIT_WORK"
}

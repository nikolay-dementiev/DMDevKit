/// The variables `devkit` gives every script: explicit paths, so that no script derives the repository from its own location.
public enum DevKitEnvironment {
    /// The git top level of the working directory `devkit` was started in.
    public static let repositoryRoot = "DEVKIT_REPO_ROOT"
    /// The folder that holds the scripts.
    public static let resources = "DEVKIT_RESOURCES"
    /// The configuration file of the repository: `<root>/devkit.conf`.
    public static let configuration = "DEVKIT_CONF"
    /// The folder scripts may write to: `<root>/.build/devkit`. It is not created.
    public static let work = "DEVKIT_WORK"
}

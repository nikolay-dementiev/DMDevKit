/// The statuses `devkit` uses for itself. 1 and 2 belong to the scripts, whose usage and configuration errors are 2 and whose
/// findings are 1, so a failure where no script ran has a status of its own, from sysexits(3).
enum DevKitStatus {
    /// EX_USAGE: no command, an unknown command, a working directory outside a git repository.
    static let usage: Int32 = 64
    /// EX_SOFTWARE: the resource folder is missing, git or the interpreter cannot start, any other failure of `devkit`.
    static let software: Int32 = 70
}

/// The exit status of `devkit` for the end of its child.
enum ExitMapping {
    /// A signal that `devkit` forwarded decides the status, then the child's exit code, then 128+n for a child that a signal
    /// ended.
    static func status(for result: LaunchResult) -> Int32 {
        if let forwarded = result.forwardedSignal {
            return 128 + forwarded
        }
        switch result.outcome {
        case .exited(let code):
            return code
        case .signaled(let signal):
            return 128 + signal
        }
    }
}

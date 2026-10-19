/// The exit status of `devkit` for the end of its child.
enum ExitMapping {
    /// A signal that `devkit` forwarded decides the status, then the child's exit code, then 128+n for a child that a signal ended.
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

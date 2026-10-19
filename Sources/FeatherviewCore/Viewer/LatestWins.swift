/// Runs jobs one at a time; a job submitted while one runs replaces any job still waiting.
/// For work that can't be stopped midway (⌘C's full-size decode): at most one runs, and the latest runs next.
@MainActor public final class LatestWins {
    private var last: Task<Void, Never>?

    public init() {}

    /// The job sees `Task.isCancelled` once a newer job is submitted.
    @discardableResult
    public func submit(_ job: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        let previous = last
        previous?.cancel()
        let task = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await job()
        }
        last = task
        return task
    }
}

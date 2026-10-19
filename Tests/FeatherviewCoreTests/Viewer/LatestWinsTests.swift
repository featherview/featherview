import Testing
@testable import FeatherviewCore

@MainActor @Suite struct LatestWinsTests {
    /// ⌘C held down: only one full-size decode at a time, and ones superseded while waiting never start.
    @Test func runsOneAtATimeAndSkipsSupersededJobs() async {
        let runner = LatestWins()
        var started: [Int] = []
        var running = 0, maxRunning = 0
        var last: Task<Void, Never>?
        func submit(_ i: Int) {
            last = runner.submit {
                started.append(i)
                running += 1
                maxRunning = max(maxRunning, running)
                // detached, like the ImageIO decode: cancelling the job doesn't stop it
                await Task.detached { try? await Task.sleep(for: .milliseconds(50)) }.value
                running -= 1
            }
        }
        submit(0)
        while started.isEmpty { await Task.yield() }
        for i in 1..<5 { submit(i) }  // job 0 can't finish meanwhile: it needs the main actor
        await last?.value
        #expect(started == [0, 4])
        #expect(maxRunning == 1)
    }
}

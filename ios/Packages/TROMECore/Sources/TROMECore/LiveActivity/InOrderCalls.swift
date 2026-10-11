/// Runs the calls of the Live Activity to the system one at a time, in the order they come:
/// an update sent after an end must never reach iOS before it.
@MainActor
final class InOrderCalls {
    private var lastCall: Task<Void, Never>?

    func waitForTheCallsInProgress() async {
        while let pending = lastCall {
            await pending.value
            if lastCall == pending {
                lastCall = nil
            }
        }
    }

    func run(_ call: @escaping @MainActor () async -> Void) async {
        let previous = lastCall
        let next = Task {
            await previous?.value
            await call()
        }
        lastCall = next
        await next.value
        if lastCall == next {
            lastCall = nil
        }
    }
}

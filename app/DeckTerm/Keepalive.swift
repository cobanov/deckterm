import BackgroundTasks
import os

/// Keeps the app running while connections are open, so going home doesn't drop them: iOS 26's continued processing
/// task, which the system shows in the Dynamic Island and on the Lock Screen, where the person can stop it. Earlier
/// iOS suspends the app in the background as before.
@available(iOS 26.0, *)
@MainActor final class Keepalive {
    static let shared = Keepalive()
    /// Info.plist's BGTaskSchedulerPermittedIdentifiers holds `<family>.*`.
    private static let family = "dev.cobanov.deckterm.connections"
    private let log = Logger(subsystem: "dev.cobanov.deckterm", category: "keepalive")
    private var submitted = false
    private var task: BGContinuedProcessingTask?
    private var ticker: Timer?
    /// The open connections' names, as the island shows them.
    private var names: [String] = []

    /// After every change to the open connections; none left ends the task.
    func update(_ names: [String]) {
        self.names = names
        guard !names.isEmpty else { return finish() }
        if let task { return task.updateTitle("DeckTerm", subtitle: subtitle) }
        if !submitted { submit() }
    }

    private var subtitle: String {
        names.count == 1 ? names[0] : String(localized: "\(names.count) connections")
    }

    /// From the foreground, as the first connection opens: the system only takes these from the app on screen.
    private func submit() {
        // A handler per request, under its own name: the system matches submissions to handlers by the exact
        // identifier, and submitting one without a handler is an assertion that ends the app.
        let identifier = Self.family + "." + UUID().uuidString
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: .main) { task in
            MainActor.assumeIsolated { self.began(task) }
        }
        guard registered else { return log.error("not kept alive: the handler wasn't registered") }
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: "DeckTerm", subtitle: subtitle)
        request.strategy = .fail
        do {
            try BGTaskScheduler.shared.submit(request)
            submitted = true
        } catch {
            log.error("not kept alive: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func began(_ task: BGTask) {
        guard let task = task as? BGContinuedProcessingTask, !names.isEmpty else {
            return task.setTaskCompleted(success: true)  // every connection closed while it waited to start
        }
        self.task = task
        task.updateTitle("DeckTerm", subtitle: subtitle)
        // shortcut: an open shell has no amount done. Indeterminate, ticked so it never reads as stalled; if iOS
        // expires it anyway, report bytes moved instead.
        task.progress.totalUnitCount = -1
        ticker = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.task?.progress.completedUnitCount += 1 }
        }
        task.expirationHandler = { [weak self, weak task] in
            // Completed, not just let go: a task left running past its time can get the app killed, not suspended,
            // and every session with it.
            task?.setTaskCompleted(success: false)
            DispatchQueue.main.async {
                self?.log.notice("expired by the system")
                self?.clear()
            }
        }
        log.notice("keeping \(self.names.count) connections alive")
    }

    private func finish() {
        task?.setTaskCompleted(success: true)
        clear()
    }

    private func clear() {
        ticker?.invalidate()
        ticker = nil
        task = nil
        submitted = false
    }
}

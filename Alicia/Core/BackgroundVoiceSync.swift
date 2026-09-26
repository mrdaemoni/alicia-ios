import UIKit
import BackgroundTasks

/// Keeps walk audio moving to the Mac when the app is not on screen.
///
/// Hector, 2026-09-26: "make sure that it runs in the background, even if the
/// app is closed." Until then the archive only synced in the foreground. A walk
/// ends with the phone locked and pocketed, so its last segments and its seal
/// waited on the phone until the next open, and the Mac, which transcribes only
/// a complete manifest and then sends it itself, waited with them.
///
/// Two layers:
///  1. **Finishing on lock.** Going to the background asks iOS for extra time
///     (`beginBackgroundTask`, roughly 30 s) and holds it until the archive has
///     nothing left in flight. Normally that is the whole tail: segments leave
///     about ten seconds after they are recorded.
///  2. **While closed.** If anything is still pending (no signal on the walk,
///     the Mac asleep, time ran out), a `BGProcessingTask` that requires the
///     network is submitted, and each run submits the next until nothing is
///     left. The notification refresh task drains the archive too. iOS decides
///     when these run. A swipe-up force-quit stops both until the next open,
///     because iOS does that to every app.
///
/// Private Body recordings are never touched: `VoiceArchive.sync` skips them.
@MainActor
enum BackgroundVoiceSync {
    static let taskID = "com.alicia.app.voicesync"

    /// The running app's store, so a background run uses the same archive the
    /// UI does instead of opening a second one over the same files.
    static weak var store: AppStore?

    /// Must run before launch finishes, like `ProactiveNotifier.register()`.
    nonisolated static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: .main) { task in
            guard let processing = task as? BGProcessingTask else { return }
            MainActor.assumeIsolated { handle(processing) }
        }
    }

    static func schedule() {
        let request = BGProcessingTaskRequest(identifier: taskID)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    /// Called on every transition to the background.
    static func finishInBackground(_ store: AppStore) {
        guard !store.isMock else { return }
        let token = BackgroundTime()
        let work = Task { @MainActor in
            // The walk seals itself in the same phase change; let that land
            // before the pass starts so the seal goes out with the tail.
            await Task.yield()
            await drain(store.voiceArchive, sync: { await store.syncVoiceArchive() })
            if store.voiceArchive.hasPendingSync { schedule() }
            token.end()
        }
        token.begin {
            work.cancel()
            schedule()
        }
    }

    /// One background pass for whichever archive is available. Returns whether
    /// everything reached the Mac.
    @discardableResult
    static func run() async -> Bool {
        if let store, !store.isMock {
            await drain(store.voiceArchive, sync: { await store.syncVoiceArchive() })
            return !store.voiceArchive.hasPendingSync
        }
        guard let service = AliciaConfig.makeService() as? LiveAliciaService else { return true }
        let archive = VoiceArchive()
        guard archive.hasPendingSync else { return true }
        await drain(archive, sync: {
            await archive.sync(using: service)
            await archive.advanceProcessing(using: service)
        })
        return !archive.hasPendingSync
    }

    /// Syncs, then waits out any pass that was already running. `sync` returns
    /// at once when another pass holds the archive, and that pass must not be
    /// abandoned when the background time is released. A few passes, not one:
    /// the seal is written while the first may already be past that recording.
    private static func drain(_ archive: VoiceArchive, sync: () async -> Void) async {
        for _ in 0..<3 {
            await sync()
            while !Task.isCancelled, archive.syncing || archive.processing {
                try? await Task.sleep(for: .milliseconds(250))
            }
            if Task.isCancelled || !archive.hasPendingSync { return }
        }
    }

    private static func handle(_ task: BGProcessingTask) {
        let work = Task { @MainActor in
            let done = await run()
            if !done { schedule() }
            task.setTaskCompleted(success: done)
        }
        task.expirationHandler = {
            work.cancel()
            Task { @MainActor in schedule() }
        }
    }
}

/// A `beginBackgroundTask` that is ended exactly once, whichever of the
/// finished work or iOS's expiration gets there first.
@MainActor
private final class BackgroundTime {
    private var id: UIBackgroundTaskIdentifier = .invalid

    func begin(onExpire: @escaping @MainActor () -> Void) {
        id = UIApplication.shared.beginBackgroundTask(withName: "alicia.voice-sync") { [weak self] in
            MainActor.assumeIsolated {
                onExpire()
                self?.end()
            }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}

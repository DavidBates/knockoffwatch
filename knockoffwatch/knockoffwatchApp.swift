import SwiftUI
import BackgroundTasks

@main
struct knockoffwatchApp: App {
    @State private var bluetooth = BluetoothManager()

    init() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BluetoothManager.bgSyncTaskIdentifier,
            using: nil
        ) { task in
            guard let bgTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            if let manager = BluetoothManager.shared {
                manager.handleBackgroundSync(task: bgTask)
            } else {
                bgTask.setTaskCompleted(success: false)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(bluetooth)
        }
    }
}

// MARK: - Root routing view

private struct RootView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        if hasCompletedOnboarding {
            MainAppView()
        } else {
            OnboardingView()
        }
    }
}

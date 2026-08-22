import AppKit
import SwiftUI
import VoltaicaCore

@main
struct VoltaicaApp: App {
    private let model = AppModel.shared
    private let preferences = Preferences.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environment(model)
                .environment(preferences)
                .paywallPresenter(model)
                .task { model.start() }
        } label: {
            StatusItemLabel(charge: preferences.showHardwarePercentage
                                    ? model.snapshot.rawPercentage
                                    : model.snapshot.controlPercentage,
                            mode: model.decision.mode,
                            showPercentage: preferences.showPercentage,
                            coloured: preferences.colouredIcon,
                            limit: model.configuration.clampedLimit,
                            limitActive: model.configuration.isLimitActive)
        }
        .menuBarExtraStyle(.window)

        Window("Voltaica", id: "dashboard") {
            DashboardView()
                .environment(model)
                .environment(preferences)
                .paywallPresenter(model)
                .task { model.start() }
        }
        .defaultSize(width: 880, height: 760)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Window("Voltaica Settings", id: "settings") {
            SettingsWindow()
                .environment(model)
                .environment(preferences)
                .paywallPresenter(model)
        }
        .defaultSize(width: 560, height: 640)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Window("Voltaica Pro", id: "unlock") {
            UnlockView()
                .environment(model)
                .environment(preferences)
        }
        .defaultSize(width: 520, height: 700)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        Window("About Voltaica", id: "about") {
            AboutView()
                .environment(model)
                .environment(preferences)
        }
        .defaultSize(width: 420, height: 470)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

/// The app has no dock icon, so the first run window is created here rather than as a scene:
/// SwiftUI has no way to present a window conditionally at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var onboarding: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let directory = DevRender.requestedDirectory {
            DevRender.run(into: directory)
            NSApp.terminate(nil)
            return
        }
        AppModel.shared.start()
        if !Preferences.shared.hasSeenOnboarding {
            presentOnboarding()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        return true
    }

    private func presentOnboarding() {
        let view = OnboardingView { [weak self] in
            self?.onboarding?.close()
            self?.onboarding = nil
        }
        .environment(AppModel.shared)
        .environment(Preferences.shared)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered,
                              defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboarding = window
    }
}

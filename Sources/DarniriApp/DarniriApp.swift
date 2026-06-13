import AppKit
import Darniri
import SwiftUI

@main
struct DarniriApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var bootstrap: AppBootstrapState

    init() {
        let bootstrap = AppBootstrapState()
        _bootstrap = State(wrappedValue: bootstrap)
        AppDelegate.sharedBootstrap = bootstrap
    }

    var body: some Scene {
        Settings {
            SettingsSceneRedirectView(bootstrap: bootstrap)
        }
    }
}

import SwiftUI

@main
struct YamahaVolumeChangerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView() // 設定画面不要
        }
    }
}

import SwiftUI

@main
struct NetScopeApp: App {
    @StateObject private var store = NetScopeStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(store)
                .onAppear {
                    store.startMonitoringIfNeeded()
                }
        } label: {
            MenuBarLabelView(downloadBps: store.totalDownloadBps, uploadBps: store.totalUploadBps)
                .onAppear {
                    store.startMonitoringIfNeeded()
                }
        }
        .menuBarExtraStyle(.window)

        Window("NetScope Dashboard", id: "dashboard") {
            DashboardView()
                .environmentObject(store)
                .onAppear {
                    store.startMonitoringIfNeeded()
                }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

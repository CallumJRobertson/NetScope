import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: NetScopeStore

    var body: some View {
        DashboardView()
            .environmentObject(store)
    }
}

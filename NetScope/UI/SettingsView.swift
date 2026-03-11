import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: NetScopeStore

    var body: some View {
        Form {
            Section("Monitoring") {
                Stepper(
                    value: Binding(
                        get: { store.refreshIntervalSeconds },
                        set: { store.setRefreshInterval($0) }
                    ),
                    in: 1...5,
                    step: 1
                ) {
                    Text("Refresh Interval: \(Int(store.refreshIntervalSeconds))s")
                }

                Stepper(
                    value: Binding(
                        get: { store.maxVisibleApps },
                        set: { store.setMaxVisibleApps($0) }
                    ),
                    in: 3...20,
                    step: 1
                ) {
                    Text("Visible App Rows: \(store.maxVisibleApps)")
                }

                if store.isPerAppMonitoringAvailable {
                    Toggle(
                        "Include system processes",
                        isOn: Binding(
                            get: { store.includeSystemProcesses },
                            set: { store.setIncludeSystemProcesses($0) }
                        )
                    )
                } else {
                    Text("Per-app monitoring is currently unavailable.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(
                    "Show Processes tab (advanced)",
                    isOn: Binding(
                        get: { store.showProcessesTab },
                        set: { store.setShowProcessesTab($0) }
                    )
                )
            }

            Section("Alerts") {
                Toggle(
                    "Enable high-bandwidth alerts",
                    isOn: Binding(
                        get: { store.alertsEnabled },
                        set: { store.setAlertsEnabled($0) }
                    )
                )

                Stepper(
                    value: Binding(
                        get: { store.alertThresholdMbps },
                        set: { store.setAlertThresholdMbps($0) }
                    ),
                    in: 5...2_000,
                    step: 5
                ) {
                    Text("Alert Threshold: \(Int(store.alertThresholdMbps)) Mbps")
                }
            }

            Section("Speed Test") {
                Button("Run Speed Test") {
                    store.runSpeedTest()
                }
                .disabled(store.isSpeedTestRunning)

                Button("Clear Speed Test History", role: .destructive) {
                    store.clearSpeedTestHistory()
                }
                .disabled(store.speedTestHistory.isEmpty)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 420, minHeight: 260)
    }
}

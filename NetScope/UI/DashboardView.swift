import AppKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: NetScopeStore

    var body: some View {
        TabView {
            OverviewTab()
                .tabItem {
                    Label("Overview", systemImage: "chart.line.uptrend.xyaxis")
                }

            ApplicationsTab()
                .tabItem {
                    Label("Applications", systemImage: "app.connected.to.app.below.fill")
                }

            if store.showProcessesTab {
                ProcessesTab()
                    .tabItem {
                        Label("Processes", systemImage: "list.bullet.rectangle")
                    }
            }

            SpeedTestsTab()
                .tabItem {
                    Label("Speed Tests", systemImage: "speedometer")
                }

            TopConsumersTab()
                .tabItem {
                    Label("Top Consumers", systemImage: "bolt.horizontal.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        .frame(minWidth: 820, minHeight: 560)
    }
}

private struct OverviewTab: View {
    @EnvironmentObject private var store: NetScopeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 20) {
                overviewStat(title: "Download", value: NetScopeFormatters.rate(bitsPerSecond: store.totalDownloadBps), color: .green)
                overviewStat(title: "Upload", value: NetScopeFormatters.rate(bitsPerSecond: store.totalUploadBps), color: .orange)
            }

            ThroughputGraphView(samples: store.graphSamples, mode: store.graphMode)

            if let monitorInfo = store.monitorInfoMessage {
                Text(monitorInfo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Picker("Mode", selection: $store.graphMode) {
                    ForEach(GraphMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Window", selection: $store.graphDuration) {
                    ForEach(GraphDuration.allCases) { duration in
                        Text(duration.label).tag(duration)
                    }
                }
                .pickerStyle(.segmented)
            }

            Spacer()
        }
        .padding()
    }

    private func overviewStat(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}

private struct ApplicationsTab: View {
    @EnvironmentObject private var store: NetScopeStore

    var body: some View {
        if !store.isPerAppMonitoringAvailable {
            VStack(alignment: .leading, spacing: 10) {
                Text("Per-application monitoring is temporarily unavailable.")
                    .font(.headline)
                Text("Total bandwidth is still shown in Overview and the menu bar.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding()
        } else {
            List(store.appRows) { row in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        HStack(spacing: 8) {
                            appIcon(for: row)
                            Text(row.appName)
                                .font(.headline)
                        }
                        Text(row.processCount == 1 ? "1 process" : "\(row.processCount) processes")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\u{2193} \(NetScopeFormatters.rate(bitsPerSecond: row.downloadBps))")
                            .font(.subheadline)
                        Text("\u{2191} \(NetScopeFormatters.rate(bitsPerSecond: row.uploadBps))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let bundleIdentifier = row.bundleIdentifier {
                        Text(bundleIdentifier)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Session: \u{2193} \(NetScopeFormatters.bytes(row.sessionDownloadBytes)) | \u{2191} \(NetScopeFormatters.bytes(row.sessionUploadBytes))")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !row.connections.isEmpty {
                        ForEach(row.connections.prefix(5)) { connection in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(connection.protocolName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Text(connection.remoteAddress)
                                        .font(.caption)
                                    if let port = connection.remotePort {
                                        Text(":\(port)")
                                            .font(.caption)
                                    }
                                    Spacer()
                                    Text(connection.state)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                if let host = store.hostname(for: connection.remoteAddress) {
                                    Text("↳ \(host)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    @ViewBuilder
    private func appIcon(for row: AppUsageRow) -> some View {
        if let nsImage = appIconImage(for: row) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: "app.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
        }
    }

    private func appIconImage(for row: AppUsageRow) -> NSImage? {
        if let bundleIdentifier = row.bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }

        if let icon = NSRunningApplication(processIdentifier: pid_t(row.pid))?.icon {
            return icon
        }

        return nil
    }
}

private struct TopConsumersTab: View {
    @EnvironmentObject private var store: NetScopeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Top Downloaders")
                    .font(.headline)
                Spacer()
                Button("Reset Session Data", role: .destructive) {
                    store.resetSessionData()
                }
            }

            List {
                Section("Download") {
                    ForEach(store.topDownloadConsumers) { consumer in
                        HStack {
                            Text(consumer.appName)
                            Spacer()
                            Text(NetScopeFormatters.bytes(consumer.totalBytes))
                                .monospacedDigit()
                        }
                    }
                }

                Section("Upload") {
                    ForEach(store.topUploadConsumers) { consumer in
                        HStack {
                            Text(consumer.appName)
                            Spacer()
                            Text(NetScopeFormatters.bytes(consumer.totalBytes))
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .padding()
    }
}

private struct ProcessesTab: View {
    @EnvironmentObject private var store: NetScopeStore

    var body: some View {
        if !store.isPerAppMonitoringAvailable {
            VStack(alignment: .leading, spacing: 10) {
                Text("Process-level monitoring is temporarily unavailable.")
                    .font(.headline)
                Spacer()
            }
            .padding()
        } else {
            List(store.processRows) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.appName)
                            .font(.headline)
                        Text("PID \(row.pid)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("↓ \(NetScopeFormatters.rate(bitsPerSecond: row.downloadBps))")
                            .font(.subheadline)
                        Text("↑ \(NetScopeFormatters.rate(bitsPerSecond: row.uploadBps))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }
}

private struct SpeedTestsTab: View {
    @EnvironmentObject private var store: NetScopeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button(store.isSpeedTestRunning ? "Running..." : "Run Speed Test") {
                    store.runSpeedTest()
                }
                .disabled(store.isSpeedTestRunning)

                Text(store.speedTestPhase.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let error = store.speedTestErrorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            List(store.speedTestHistory) { result in
                HStack {
                    Text(result.date, style: .date)
                    Spacer()
                    Text("Ping \(NetScopeFormatters.ping(result.pingMS))")
                    Text("\u{2193} \(NetScopeFormatters.megabits(result.downloadMbps))")
                    Text("\u{2191} \(NetScopeFormatters.megabits(result.uploadMbps))")
                }
                .font(.subheadline)
            }
        }
        .padding()
    }
}

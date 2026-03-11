import AppKit
import Charts
import SwiftUI

struct MenuBarLabelView: View {
    let downloadBps: Double
    let uploadBps: Double

    var body: some View {
        Text("\u{2193}\(NetScopeFormatters.compactRate(bitsPerSecond: downloadBps)) \u{2191}\(NetScopeFormatters.compactRate(bitsPerSecond: uploadBps))")
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
    }
}

struct MenuBarContentView: View {
    @EnvironmentObject private var store: NetScopeStore
    @Environment(\.openWindow) private var openWindow

    @State private var expandedRows: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                throughputHeader
                graphSection
                applicationsSection
                speedTestSection
                topConsumersSection
                actionsSection
            }
            .padding(14)
        }
        .frame(width: 430, height: 620)
    }

    private var throughputHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Total Network Usage")
                .font(.headline)

            HStack(spacing: 16) {
                statBlock(title: "Download", value: NetScopeFormatters.rate(bitsPerSecond: store.totalDownloadBps), color: .green)
                statBlock(title: "Upload", value: NetScopeFormatters.rate(bitsPerSecond: store.totalUploadBps), color: .orange)
            }

            if let monitorErrorMessage = store.monitorErrorMessage {
                Text(monitorErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let monitorInfoMessage = store.monitorInfoMessage {
                Text(monitorInfoMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var graphSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Live Bandwidth")
                .font(.headline)

            ThroughputGraphView(samples: store.graphSamples, mode: store.graphMode)

            Picker("Graph Mode", selection: $store.graphMode) {
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
    }

    private var applicationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Applications Using Network")
                .font(.headline)

            if !store.isPerAppMonitoringAvailable {
                Text("Per-application monitoring is temporarily unavailable.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else if store.visibleAppRows.isEmpty {
                Text("No active application traffic detected.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.visibleAppRows) { row in
                        DisclosureGroup(isExpanded: binding(for: row.id)) {
                            VStack(alignment: .leading, spacing: 4) {
                                if let bundleIdentifier = row.bundleIdentifier {
                                    Text(bundleIdentifier)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Text("Session \u{2193} \(NetScopeFormatters.bytes(row.sessionDownloadBytes)) | \u{2191} \(NetScopeFormatters.bytes(row.sessionUploadBytes))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                connectionList(for: row)
                            }
                            .padding(.top, 4)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        appIcon(for: row)
                                        Text(row.appName)
                                            .font(.subheadline)
                                            .lineLimit(1)
                                    }
                                    Text(row.processCount == 1 ? "1 process" : "\(row.processCount) processes")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\u{2193} \(NetScopeFormatters.rate(bitsPerSecond: row.downloadBps))")
                                        .font(.caption)
                                    Text("\u{2191} \(NetScopeFormatters.rate(bitsPerSecond: row.uploadBps))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disclosureGroupStyle(.automatic)

                        Divider()
                    }
                }
            }
        }
    }

    private var speedTestSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Speed Test")
                .font(.headline)

            HStack {
                Button(store.isSpeedTestRunning ? "Running..." : "Run Internet Speed Test") {
                    store.runSpeedTest()
                }
                .disabled(store.isSpeedTestRunning)

                Spacer()

                Text(store.speedTestPhase.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let speedTestErrorMessage = store.speedTestErrorMessage {
                Text(speedTestErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let result = store.currentSpeedTestResult {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ping: \(NetScopeFormatters.ping(result.pingMS))")
                    Text("Download: \(NetScopeFormatters.megabits(result.downloadMbps))")
                    Text("Upload: \(NetScopeFormatters.megabits(result.uploadMbps))")
                }
                .font(.caption)

                Divider()

                ForEach(store.speedTestHistory.prefix(4)) { entry in
                    HStack {
                        Text(entry.date, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\u{2193} \(NetScopeFormatters.megabits(entry.downloadMbps))")
                            .font(.caption)
                        Text("\u{2191} \(NetScopeFormatters.megabits(entry.uploadMbps))")
                            .font(.caption)
                    }
                }
            }
        }
    }

    private var topConsumersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Top Consumers (Session)")
                .font(.headline)

            if store.topDownloadConsumers.isEmpty && store.topUploadConsumers.isEmpty {
                Text("Top consumer data will appear after traffic is detected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Download")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(store.topDownloadConsumers.prefix(3)) { consumer in
                            Text("\(consumer.appName) - \(NetScopeFormatters.bytes(consumer.totalBytes))")
                                .font(.caption)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Upload")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(store.topUploadConsumers.prefix(3)) { consumer in
                            Text("\(consumer.appName) - \(NetScopeFormatters.bytes(consumer.totalBytes))")
                                .font(.caption)
                        }
                    }
                }
            }
        }
    }

    private var actionsSection: some View {
        HStack {
            Button("Open Full Dashboard") {
                openWindow(id: "dashboard")
            }

            SettingsLink {
                Text("Preferences")
            }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func statBlock(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(color)
        }
    }

    @ViewBuilder
    private func connectionList(for row: AppUsageRow) -> some View {
        if row.connections.isEmpty {
            Text("No active destinations detected")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(row.connections.prefix(8)) { connection in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(connection.protocolName)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        Text(connection.remoteAddress)
                            .font(.caption)
                            .lineLimit(1)

                        if let port = connection.remotePort {
                            Text(":\(port)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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

            if row.connections.count > 8 {
                Text("+\(row.connections.count - 8) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(for rowID: String) -> Binding<Bool> {
        Binding(
            get: { expandedRows.contains(rowID) },
            set: { isExpanded in
                if isExpanded {
                    expandedRows.insert(rowID)
                } else {
                    expandedRows.remove(rowID)
                }
            }
        )
    }

    @ViewBuilder
    private func appIcon(for row: AppUsageRow) -> some View {
        if let nsImage = appIconImage(for: row) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: "app.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
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

struct ThroughputGraphView: View {
    let samples: [ThroughputSample]
    let mode: GraphMode

    private var chartValues: [ThroughputSample] {
        samples.sorted { $0.timestamp < $1.timestamp }
    }

    private var maxMbps: Double {
        let maxBps = chartValues.map { mode.value(for: $0) }.max() ?? 1
        return max(1, maxBps / 1_000_000)
    }

    var body: some View {
        Chart(chartValues) { sample in
            LineMark(
                x: .value("Time", sample.timestamp),
                y: .value("Mbps", mode.value(for: sample) / 1_000_000)
            )
            .foregroundStyle(mode.color)
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("Time", sample.timestamp),
                y: .value("Mbps", mode.value(for: sample) / 1_000_000)
            )
            .foregroundStyle(mode.color.opacity(0.15))
            .interpolationMethod(.catmullRom)
        }
        .chartXAxis(.hidden)
        .chartYScale(domain: 0...(maxMbps * 1.2))
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .frame(height: 120)
    }
}

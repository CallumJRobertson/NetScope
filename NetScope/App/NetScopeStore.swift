import AppKit
import Combine
import Darwin
import Foundation

@MainActor
final class NetScopeStore: ObservableObject {
    private struct ProcessIdentity {
        let appName: String
        let bundleIdentifier: String?
        let groupKey: String
        let isUserFacing: Bool
    }

    @Published private(set) var appRows: [AppUsageRow] = []
    @Published private(set) var processRows: [AppUsageRow] = []
    @Published private(set) var totalDownloadBps: Double = 0
    @Published private(set) var totalUploadBps: Double = 0
    @Published private(set) var throughputSamples: [ThroughputSample] = []
    @Published private(set) var monitorErrorMessage: String?
    @Published private(set) var monitorInfoMessage: String?
    @Published private(set) var isPerAppMonitoringAvailable = true
    @Published private(set) var topDownloadConsumers: [TopConsumer] = []
    @Published private(set) var topUploadConsumers: [TopConsumer] = []
    @Published private(set) var resolvedHostsByAddress: [String: String] = [:]

    @Published var graphMode: GraphMode = .total
    @Published var graphDuration: GraphDuration = .fiveMinutes

    @Published private(set) var speedTestPhase: SpeedTestPhase = .idle
    @Published private(set) var speedTestHistory: [SpeedTestResult]
    @Published private(set) var speedTestErrorMessage: String?
    @Published private(set) var isSpeedTestRunning = false

    @Published private(set) var refreshIntervalSeconds: Double
    @Published private(set) var maxVisibleApps: Int
    @Published private(set) var includeSystemProcesses: Bool
    @Published private(set) var alertsEnabled: Bool
    @Published private(set) var alertThresholdMbps: Double
    @Published private(set) var showProcessesTab: Bool

    private let nettopSampler = NettopSampler()
    private let interfaceSampler = InterfaceBandwidthSampler()
    private let speedTestService = CloudflareSpeedTestService()
    private let resolver = ReverseDNSResolver()
    private let notifier = AlertNotifier()
    private let defaults: UserDefaults

    private var monitorTask: Task<Void, Never>?
    private var sessionTotalsByPID: [Int: (download: UInt64, upload: UInt64)] = [:]
    private var lastAlertAtByPID: [Int: Date] = [:]
    private var hasStartedMonitoring = false
    private var smoothedDownloadBps: Double = 0
    private var smoothedUploadBps: Double = 0

    private enum DefaultsKey {
        static let refreshInterval = "monitor.refreshInterval"
        static let maxVisibleApps = "monitor.maxVisibleApps"
        static let includeSystem = "monitor.includeSystemProcesses"
        static let alertsEnabled = "alerts.enabled"
        static let alertsThresholdMbps = "alerts.thresholdMbps"
        static let showProcessesTab = "ui.showProcessesTab"
        static let speedHistory = "speedtest.history"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let storedInterval = defaults.object(forKey: DefaultsKey.refreshInterval) as? Double ?? 1.0
        let storedMaxApps = defaults.object(forKey: DefaultsKey.maxVisibleApps) as? Int ?? 8
        let storedSystemFlag = defaults.object(forKey: DefaultsKey.includeSystem) as? Bool ?? false
        let storedAlertsEnabled = defaults.object(forKey: DefaultsKey.alertsEnabled) as? Bool ?? false
        let storedThreshold = defaults.object(forKey: DefaultsKey.alertsThresholdMbps) as? Double ?? 50.0
        let storedShowProcessesTab = defaults.object(forKey: DefaultsKey.showProcessesTab) as? Bool ?? false

        refreshIntervalSeconds = min(max(storedInterval, 1), 5)
        maxVisibleApps = min(max(storedMaxApps, 3), 20)
        includeSystemProcesses = storedSystemFlag
        alertsEnabled = storedAlertsEnabled
        alertThresholdMbps = min(max(storedThreshold, 5), 2_000)
        showProcessesTab = storedShowProcessesTab
        speedTestHistory = NetScopeStore.loadSpeedTestHistory(defaults: defaults)
    }

    deinit {
        monitorTask?.cancel()
    }

    var visibleAppRows: [AppUsageRow] {
        Array(appRows.prefix(maxVisibleApps))
    }

    var currentSpeedTestResult: SpeedTestResult? {
        speedTestHistory.first
    }

    var graphSamples: [ThroughputSample] {
        let cutoff = Date().addingTimeInterval(-graphDuration.windowSeconds)
        return throughputSamples.filter { $0.timestamp >= cutoff }
    }

    func hostname(for address: String) -> String? {
        resolvedHostsByAddress[address]
    }

    func startMonitoringIfNeeded() {
        guard !hasStartedMonitoring else {
            return
        }
        hasStartedMonitoring = true
        startMonitoring()
    }

    func resetSessionData() {
        sessionTotalsByPID.removeAll()
        topDownloadConsumers = []
        topUploadConsumers = []
        lastAlertAtByPID.removeAll()
        smoothedDownloadBps = 0
        smoothedUploadBps = 0
        appRows = []
        processRows = []
        totalDownloadBps = 0
        totalUploadBps = 0
        throughputSamples = []
    }

    func setRefreshInterval(_ value: Double) {
        let clamped = min(max(value, 1), 5)
        guard abs(clamped - refreshIntervalSeconds) > 0.001 else {
            return
        }

        refreshIntervalSeconds = clamped
        defaults.set(clamped, forKey: DefaultsKey.refreshInterval)
        restartMonitoring()
    }

    func setMaxVisibleApps(_ value: Int) {
        let clamped = min(max(value, 3), 20)
        guard clamped != maxVisibleApps else {
            return
        }

        maxVisibleApps = clamped
        defaults.set(clamped, forKey: DefaultsKey.maxVisibleApps)
    }

    func setIncludeSystemProcesses(_ value: Bool) {
        guard value != includeSystemProcesses else {
            return
        }

        includeSystemProcesses = value
        defaults.set(value, forKey: DefaultsKey.includeSystem)
    }

    func setAlertsEnabled(_ value: Bool) {
        guard value != alertsEnabled else {
            return
        }

        alertsEnabled = value
        defaults.set(value, forKey: DefaultsKey.alertsEnabled)
    }

    func setAlertThresholdMbps(_ value: Double) {
        let clamped = min(max(value, 5), 2_000)
        guard abs(clamped - alertThresholdMbps) > 0.001 else {
            return
        }

        alertThresholdMbps = clamped
        defaults.set(clamped, forKey: DefaultsKey.alertsThresholdMbps)
    }

    func setShowProcessesTab(_ value: Bool) {
        guard value != showProcessesTab else {
            return
        }

        showProcessesTab = value
        defaults.set(value, forKey: DefaultsKey.showProcessesTab)
    }

    func runSpeedTest() {
        guard !isSpeedTestRunning else {
            return
        }

        isSpeedTestRunning = true
        speedTestErrorMessage = nil

        Task {
            do {
                speedTestPhase = .ping
                let ping = try await speedTestService.measurePingMS()

                speedTestPhase = .download
                let download = try await speedTestService.measureDownloadMbps()

                speedTestPhase = .upload
                let upload = try await speedTestService.measureUploadMbps()

                let result = SpeedTestResult(date: Date(), pingMS: ping, downloadMbps: download, uploadMbps: upload)
                speedTestHistory.insert(result, at: 0)
                speedTestHistory = Array(speedTestHistory.prefix(30))
                persistSpeedTestHistory()

                speedTestPhase = .completed
            } catch {
                speedTestPhase = .failed
                speedTestErrorMessage = error.localizedDescription
            }

            isSpeedTestRunning = false
        }
    }

    func clearSpeedTestHistory() {
        speedTestHistory.removeAll()
        persistSpeedTestHistory()
    }

    private func startMonitoring() {
        monitorTask?.cancel()

        let interval = refreshIntervalSeconds
        let nettopSampler = self.nettopSampler
        let interfaceSampler = self.interfaceSampler

        monitorTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                let timestamp = Date()

                do {
                    let deltas = try await nettopSampler.sample(interval: interval)
                    guard let self else {
                        return
                    }
                    await self.consumeMonitorSample(deltas, at: timestamp)
                } catch {
                    guard let self else {
                        return
                    }

                    do {
                        let rates = try await interfaceSampler.sample(interval: interval)
                        await self.consumeFallbackTotalSample(downloadBps: rates.downloadBps, uploadBps: rates.uploadBps, error: error, at: timestamp)
                        try? await Task.sleep(for: .seconds(interval))
                    } catch {
                        await self.consumeMonitorError(error)
                        try? await Task.sleep(for: .seconds(2))
                    }
                }
            }
        }
    }

    private func restartMonitoring() {
        hasStartedMonitoring = true
        resetSessionData()
        startMonitoring()
    }

    private func consumeMonitorSample(_ deltas: [ProcessDeltaSnapshot], at timestamp: Date) {
        var nextSessionTotals = sessionTotalsByPID
        var processRows: [AppUsageRow] = []
        processRows.reserveCapacity(deltas.count)

        var totalDownload: Double = 0
        var totalUpload: Double = 0

        for delta in deltas {
            let previousTotal = nextSessionTotals[delta.process.pid] ?? (download: 0, upload: 0)
            let updatedTotal = (
                download: previousTotal.download + delta.deltaDownloadBytes,
                upload: previousTotal.upload + delta.deltaUploadBytes
            )
            nextSessionTotals[delta.process.pid] = updatedTotal

            totalDownload += delta.downloadBps
            totalUpload += delta.uploadBps

            let runningApplication = NSRunningApplication(processIdentifier: pid_t(delta.process.pid))
            let identity = processIdentity(forPID: delta.process.pid, processName: delta.process.processName, runningApplication: runningApplication)
            guard shouldIncludeProcess(identity) else {
                continue
            }

            let sortedConnections = delta.process.connections.sorted { lhs, rhs in
                if lhs.remoteAddress == rhs.remoteAddress {
                    return (lhs.remotePort ?? 0) < (rhs.remotePort ?? 0)
                }
                return lhs.remoteAddress < rhs.remoteAddress
            }

            let row = AppUsageRow(
                id: "pid:\(delta.process.pid)",
                pid: delta.process.pid,
                groupKey: identity.groupKey,
                processCount: 1,
                appName: identity.appName,
                bundleIdentifier: identity.bundleIdentifier,
                downloadBps: delta.downloadBps,
                uploadBps: delta.uploadBps,
                sessionDownloadBytes: updatedTotal.download,
                sessionUploadBytes: updatedTotal.upload,
                connections: sortedConnections
            )

            processRows.append(row)
        }

        sessionTotalsByPID = nextSessionTotals
        self.processRows = processRows.sorted { lhs, rhs in
            (lhs.downloadBps + lhs.uploadBps) > (rhs.downloadBps + rhs.uploadBps)
        }
        appRows = aggregateRowsByApplication(processRows).sorted { lhs, rhs in
            (lhs.downloadBps + lhs.uploadBps) > (rhs.downloadBps + rhs.uploadBps)
        }

        let alpha = 0.35
        smoothedDownloadBps = (smoothedDownloadBps * (1 - alpha)) + (totalDownload * alpha)
        smoothedUploadBps = (smoothedUploadBps * (1 - alpha)) + (totalUpload * alpha)
        totalDownloadBps = smoothedDownloadBps
        totalUploadBps = smoothedUploadBps
        isPerAppMonitoringAvailable = true
        monitorInfoMessage = nil
        monitorErrorMessage = nil

        throughputSamples.append(
            ThroughputSample(
                timestamp: timestamp,
                downloadBps: totalDownloadBps,
                uploadBps: totalUploadBps
            )
        )

        updateTopConsumers(from: appRows)
        evaluateAlerts(for: appRows)
        resolveVisibleHostnames(from: appRows)
        trimHistory()
    }

    private func consumeFallbackTotalSample(downloadBps: Double, uploadBps: Double, error: Error, at timestamp: Date) {
        appRows = []
        processRows = []
        let alpha = 0.35
        smoothedDownloadBps = (smoothedDownloadBps * (1 - alpha)) + (downloadBps * alpha)
        smoothedUploadBps = (smoothedUploadBps * (1 - alpha)) + (uploadBps * alpha)
        totalDownloadBps = smoothedDownloadBps
        totalUploadBps = smoothedUploadBps
        isPerAppMonitoringAvailable = false
        monitorInfoMessage = "Per-app monitor unavailable right now. Showing interface totals."
        monitorErrorMessage = nil

        throughputSamples.append(
            ThroughputSample(
                timestamp: timestamp,
                downloadBps: downloadBps,
                uploadBps: uploadBps
            )
        )
        trimHistory()
    }

    private func consumeMonitorError(_ error: Error) {
        monitorErrorMessage = error.localizedDescription
        totalDownloadBps = 0
        totalUploadBps = 0
    }

    private func updateTopConsumers(from rows: [AppUsageRow]) {
        topDownloadConsumers = rows
            .sorted { $0.sessionDownloadBytes > $1.sessionDownloadBytes }
            .prefix(5)
            .map { TopConsumer(id: $0.id, appName: $0.appName, totalBytes: $0.sessionDownloadBytes) }

        topUploadConsumers = rows
            .sorted { $0.sessionUploadBytes > $1.sessionUploadBytes }
            .prefix(5)
            .map { TopConsumer(id: $0.id, appName: $0.appName, totalBytes: $0.sessionUploadBytes) }
    }

    private func evaluateAlerts(for rows: [AppUsageRow]) {
        guard alertsEnabled else {
            return
        }

        let now = Date()
        let cooldown: TimeInterval = 120

        for row in rows.prefix(10) {
            let totalMbps = (row.downloadBps + row.uploadBps) / 1_000_000
            guard totalMbps >= alertThresholdMbps else {
                continue
            }

            let last = lastAlertAtByPID[row.pid] ?? .distantPast
            guard now.timeIntervalSince(last) >= cooldown else {
                continue
            }

            lastAlertAtByPID[row.pid] = now
            notifier.sendHighUsageAlert(appName: row.appName, rateMbps: totalMbps)
        }
    }

    private func resolveVisibleHostnames(from rows: [AppUsageRow]) {
        let addresses = Set(rows
            .prefix(maxVisibleApps)
            .flatMap { $0.connections.prefix(10).map(\.remoteAddress) }
            .filter { resolvedHostsByAddress[$0] == nil })

        guard !addresses.isEmpty else {
            return
        }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else {
                return
            }

            var discovered: [String: String] = [:]
            for address in addresses {
                if let host = await self.resolver.resolve(address) {
                    discovered[address] = host
                }
            }

            guard !discovered.isEmpty else {
                return
            }

            let resolved = discovered
            await MainActor.run {
                for (address, host) in resolved {
                    self.resolvedHostsByAddress[address] = host
                }
            }
        }
    }

    private func trimHistory() {
        let cutoff = Date().addingTimeInterval(-GraphDuration.thirtyMinutes.windowSeconds)
        throughputSamples.removeAll { $0.timestamp < cutoff }
    }

    private func aggregateRowsByApplication(_ rows: [AppUsageRow]) -> [AppUsageRow] {
        struct Aggregate {
            var appName: String
            var bundleIdentifier: String?
            var representativePID: Int
            var processCount: Int
            var downloadBps: Double
            var uploadBps: Double
            var sessionDownloadBytes: UInt64
            var sessionUploadBytes: UInt64
            var connections: Set<ConnectionSnapshot>
        }

        var grouped: [String: Aggregate] = [:]
        grouped.reserveCapacity(rows.count)

        for row in rows {
            let key = row.groupKey
            if var existing = grouped[key] {
                existing.processCount += 1
                existing.downloadBps += row.downloadBps
                existing.uploadBps += row.uploadBps
                existing.sessionDownloadBytes += row.sessionDownloadBytes
                existing.sessionUploadBytes += row.sessionUploadBytes
                existing.connections.formUnion(row.connections)
                grouped[key] = existing
            } else {
                grouped[key] = Aggregate(
                    appName: row.appName,
                    bundleIdentifier: row.bundleIdentifier,
                    representativePID: row.pid,
                    processCount: 1,
                    downloadBps: row.downloadBps,
                    uploadBps: row.uploadBps,
                    sessionDownloadBytes: row.sessionDownloadBytes,
                    sessionUploadBytes: row.sessionUploadBytes,
                    connections: Set(row.connections)
                )
            }
        }

        return grouped.map { key, value in
            AppUsageRow(
                id: key,
                pid: value.representativePID,
                groupKey: key,
                processCount: value.processCount,
                appName: value.appName,
                bundleIdentifier: value.bundleIdentifier,
                downloadBps: value.downloadBps,
                uploadBps: value.uploadBps,
                sessionDownloadBytes: value.sessionDownloadBytes,
                sessionUploadBytes: value.sessionUploadBytes,
                connections: Array(value.connections).sorted { lhs, rhs in
                    if lhs.remoteAddress == rhs.remoteAddress {
                        return (lhs.remotePort ?? 0) < (rhs.remotePort ?? 0)
                    }
                    return lhs.remoteAddress < rhs.remoteAddress
                }
            )
        }
    }

    private func shouldIncludeProcess(_ identity: ProcessIdentity) -> Bool {
        if !includeSystemProcesses {
            if !identity.isUserFacing {
                return false
            }
        }

        return true
    }

    private func processIdentity(forPID pid: Int, processName: String, runningApplication: NSRunningApplication?) -> ProcessIdentity {
        if let runningApplication {
            let bundleIdentifier = runningApplication.bundleIdentifier
            let appName = runningApplication.localizedName ?? processName
            let isUserFacing = runningApplication.activationPolicy != .prohibited
            let groupKey = bundleIdentifier ?? "name:\(appName.lowercased())"

            if isUserFacing {
                return ProcessIdentity(
                    appName: appName,
                    bundleIdentifier: bundleIdentifier,
                    groupKey: groupKey,
                    isUserFacing: true
                )
            }
        }

        if let inferred = inferOwningAppFromPID(pid) {
            return inferred
        }

        return ProcessIdentity(
            appName: processName,
            bundleIdentifier: nil,
            groupKey: "name:\(processName.lowercased())",
            isUserFacing: false
        )
    }

    private func inferOwningAppFromPID(_ pid: Int) -> ProcessIdentity? {
        var pathBuffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid_t(pid), &pathBuffer, UInt32(pathBuffer.count))
        guard length > 0 else {
            return nil
        }

        let executablePath = String(cString: pathBuffer)
        guard let appRange = executablePath.range(of: ".app", options: .backwards) else {
            return nil
        }

        let appPath = String(executablePath[..<appRange.upperBound])
        let appURL = URL(fileURLWithPath: appPath)
        let bundle = Bundle(url: appURL)
        let bundleIdentifier = bundle?.bundleIdentifier

        let appName =
            (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ??
            (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String) ??
            appURL.deletingPathExtension().lastPathComponent

        let loweredName = appName.lowercased()
        let isLikelyBackground = loweredName.contains("helper") || loweredName.contains("agent") || loweredName.contains("daemon")
        let isUserFacing = !isLikelyBackground
        let groupKey = bundleIdentifier ?? "app:\(appPath.lowercased())"

        return ProcessIdentity(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            groupKey: groupKey,
            isUserFacing: isUserFacing
        )
    }

    private func persistSpeedTestHistory() {
        do {
            let data = try JSONEncoder().encode(speedTestHistory)
            defaults.set(data, forKey: DefaultsKey.speedHistory)
        } catch {
            speedTestErrorMessage = "Could not save speed test history."
        }
    }

    private static func loadSpeedTestHistory(defaults: UserDefaults) -> [SpeedTestResult] {
        guard let data = defaults.data(forKey: DefaultsKey.speedHistory),
              let history = try? JSONDecoder().decode([SpeedTestResult].self, from: data) else {
            return []
        }

        return history.sorted { $0.date > $1.date }
    }
}

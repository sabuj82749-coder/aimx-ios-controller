import Foundation
import Combine
import SwiftUI

/// Companion controller state, mirroring Android `MainViewModel` in MainActivity.kt.
final class MainViewModel: ObservableObject {
    @Published var currentScreen: AppScreen = .connecting
    @Published var connectionState: ConnectionState = .disconnected
    @Published var pcIP = "192.168.1.100"
    @Published var discoveredPCs: [String] = []
    @Published var isScanning = false
    @Published var logsList: [String] = ["App initialized. Ready to launch."]
    @Published var recordingKeybindMode: String?
    @Published var keybindMasterEnabled = false
    @Published var currentKeybinds: [String: String] = [
        "head": "",
        "fair": "",
        "collider": "",
        "sniper": ""
    ]
    @Published var safeAreaTop: CGFloat = 0
    @Published var safeAreaBottom: CGFloat = 0

    private let connectionManager = PCConnectionManager()
    private let scanner = LANScanner()
    private let udpListener = UDPBroadcastListener()
    private var foregroundObserver: NSObjectProtocol?

    init() {
        connectionManager.onLog = { [weak self] message in
            self?.addLog(message)
        }
        connectionManager.onStatusChange = { [weak self] state, ip in
            self?.handleConnectionStatusChange(state, ip: ip)
        }

        udpListener.onDatagram = { [weak self] sourceIP, _ in
            self?.handleUDPDiscovery(sourceIP)
        }

        udpListener.start()

        // On iOS the Local Network permission may be granted *after* the first
        // (blocked) scan. Re-trigger discovery whenever the app returns from
        // background / Settings so a freshly granted permission takes effect.
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: .aimxDidEnterForeground,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if self.connectionState != .connected {
                self.addLog("App foreground - restarting discovery...")
                self.autoConnect()
            }
        }

        // Auto-connect on startup — no login needed (same as Android bypass mode).
        autoConnect()
    }

    deinit {
        if let foregroundObserver = foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
        }
        udpListener.stop()
        connectionManager.disconnect()
        scanner.cancel()
    }

    // MARK: - Screen + Connection wiring

    private func handleConnectionStatusChange(_ state: ConnectionState, ip: String?) {
        connectionState = state
        switch state {
        case .connected:
            if currentScreen == .connecting {
                currentScreen = .controller
            }
        case .disconnected:
            if currentScreen == .controller {
                currentScreen = .connecting
                autoConnect()
            }
        case .connecting:
            break
        }
    }

    func navigateTo(_ screen: AppScreen) {
        currentScreen = screen
    }

    func setPcIp(_ ip: String) {
        pcIP = ip
        connectionManager.setpcIP(ip)
    }

    func toggleConnection(onStatusChangeCallbacks: ((ConnectionState, String?) -> Void)? = nil) {
        if connectionState != .disconnected {
            connectionManager.disconnect()
            onStatusChangeCallbacks?(.disconnected, nil)
        } else {
            connectionManager.onStatusChange = { [weak self] state, ip in
                onStatusChangeCallbacks?(state, ip)
                self?.handleConnectionStatusChange(state, ip: ip)
            }
            connectionManager.connect()
        }
    }

    func disconnectPC() {
        connectionManager.disconnect()
        addLog("TCP Link Offline.")
    }

    // MARK: - Keybinds

    func startRecordingKeybind(mode: String) {
        recordingKeybindMode = mode
        addLog("Keybind capture active: Press buttons to map for \(mode)")
    }

    func stopRecordingKeybind() {
        recordingKeybindMode = nil
    }

    func setKeybindMasterEnabled(_ enabled: Bool) {
        keybindMasterEnabled = enabled
        addLog("Keybind Master: \(enabled ? "ENABLED" : "DISABLED")")
    }

    func updateKeybind(mode: String, keyName: String) {
        currentKeybinds[mode] = keyName
        addLog("Keybind updated: \(mode) -> \(keyName)")
    }

    func updateAllKeybinds(_ keybinds: [String: String]) {
        currentKeybinds = keybinds
        let mappings = keybinds
            .filter { !$0.value.isEmpty }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: ", ")
        if !mappings.isEmpty {
            addLog("Keybinds synced: \(mappings)")
        }
    }

    // MARK: - Logging

    func addLog(_ msg: String) {
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            var updated = self.logsList + [msg]
            if updated.count > 80 { updated.removeFirst() }
            self.logsList = updated
        }
        DispatchQueue.main.async(execute: work)
    }

    // MARK: - Discovery

    func runLanDiscovery() {
        if isScanning {
            // A previous scan may still be stuck (e.g. iOS Local Network prompt
            // unresolved). Cancel it so a user retry always starts fresh.
            scanner.cancel()
            isScanning = false
        }
        guard let localIP = getLocalIpAddress() else {
            addLog("Lan discovery failed: Wi-Fi offline or local IP unavailable")
            isScanning = false
            return
        }
        addLog("Self Local IP: \(localIP)")
        discoveredPCs = []

        scanner.start(
            localIP: localIP,
            onFound: { [weak self] host in
                guard let self = self else { return }
                if !self.discoveredPCs.contains(host) {
                    self.discoveredPCs.append(host)
                }
                // Auto-connect to the first discovered cheat PC immediately.
                if self.connectionState == .disconnected {
                    self.setPcIp(host)
                    self.connectionManager.connect()
                }
            },
            onScanChange: { [weak self] scanning in
                self?.isScanning = scanning
            },
            onLog: { [weak self] message in
                self?.addLog(message)
            }
        )
    }

    func cancelScanning() {
        scanner.cancel()
        isScanning = false
    }

    func getLocalIpAddress() -> String? {
        return LocalIP.ipv4Address()
    }

    // MARK: - Data transmission (JS bridge targets)

    func transmitJsonState(_ jsonString: String) {
        if let packet = PacketEncoder.statePacket(jsonString: jsonString) {
            connectionManager.transmit(packet)
        }
        syncKeybindsFromJson(jsonString)
    }

    func transmitPlainCommand(_ action: String, _ arg: String) {
        let packet = PacketEncoder.plainCommandPacket(action: action, arg: arg)
        connectionManager.transmit(packet)
        addLog("Action dispatched: \(action) -> \(arg)")
    }

    func sendBypassRequest() {
        let packet = PacketEncoder.plainCommandPacket(action: "pc_bypass", arg: "Requested")
        connectionManager.transmit(packet)
        addLog("PC BYPASS command dispatched")
    }

    func initializeMemory() {
        let packet = PacketEncoder.plainCommandPacket(action: "memory_init", arg: "")
        connectionManager.transmit(packet)
        addLog("Memory initialization requested")
    }

    /// Mirrors the keybind sync done inside Android's `sendStateToPC` bridge.
    private func syncKeybindsFromJson(_ jsonString: String) {
        guard
            let data = jsonString.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let keybinds = object["keybinds"] as? [String: Any]
        else {
            return
        }
        if let active = keybinds["active"] as? Bool {
            setKeybindMasterEnabled(active)
        }
        if let keys = keybinds["keys"] as? [String: Any] {
            var updated: [String: String] = [:]
            for (key, value) in keys {
                updated[key] = value as? String ?? ""
            }
            if !updated.isEmpty {
                updateAllKeybinds(updated)
            }
        }
    }

    private func handleUDPDiscovery(_ sourceIP: String) {
        if !discoveredPCs.contains(sourceIP) {
            discoveredPCs.append(sourceIP)
            addLog("Auto-found PC via UDP Broadcast: \(sourceIP)")
        }
        if connectionState == .disconnected {
            setPcIp(sourceIP)
            connectionManager.connect()
        }
    }

    func autoConnect() {
        if connectionState == .connected { return }
        addLog("Auto-connecting to cheat PC...")
        runLanDiscovery()
        connectionManager.autoConnect(withDiscovery: { [weak self] in
            self?.runLanDiscovery()
        })
    }
}